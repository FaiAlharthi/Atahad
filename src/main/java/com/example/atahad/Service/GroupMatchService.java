package com.example.atahad.Service;

import com.example.atahad.AI.AiService;

import com.example.atahad.Api.ApiException;
import com.example.atahad.Dto.Out.GroupMatchResponse;
import com.example.atahad.Dto.Out.SimilarGroupResponse;
import com.example.atahad.Entity.*;
import com.example.atahad.Repository.*;
import com.example.atahad.Service.GroupGoalService.MemberWeek;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.DayOfWeek;
import java.time.Duration;
import java.time.LocalDate;
import java.time.temporal.TemporalAdjusters;
import java.util.*;

// optional competitions between two groups for one week (sunday to saturday), points only, no money
@Service
@RequiredArgsConstructor
public class GroupMatchService {
    private final GroupMatchRepository groupMatchRepository;
    private final GroupRepository groupRepository;
    private final GroupGoalRepository groupGoalRepository;
    private final GroupAccessService groupAccessService;
    private final GroupGoalService groupGoalService;
    private final PointLogService pointLogService;
    private final AiService aiService;

    // groups that look like ours: same proof method, close size, similar goal words
    public List<SimilarGroupResponse> suggestOpponents(Integer groupId, Integer memberId){

        groupAccessService.getActiveMembership(groupId, memberId);

        GroupGoal ourGoal = groupGoalRepository.findGroupGoalByGroupIdAndStatus(groupId, "ACTIVE");
        if(ourGoal == null){
            throw new ApiException("Your group must have an active goal");
        }

        int ourSize = groupAccessService.activeMembersCount(groupId);
        if(ourSize < GroupAccessService.MIN_MEMBERS){
            throw new ApiException("Your group must have at least 2 members");
        }

        List<SimilarGroupResponse> list = new ArrayList<>();
        Map<Integer, Integer> scores = new HashMap<>();

        for(GroupGoal goal : groupGoalRepository.findGroupGoalsByStatus("ACTIVE")){

            Group other = goal.getGroup();
            System.out.println("Checking Group: " + other.getName());

            if(other.getId().equals(groupId) || !"ACTIVE".equals(other.getStatus())){
                continue;
            }

            if(hasOpenMatch(groupId, other.getId()) || hasActiveMatch(other.getId(), null)){
                continue; // one match at a time: a group in a match is not suggested
            }

            int size = groupAccessService.activeMembersCount(other.getId());

            if(size < GroupAccessService.MIN_MEMBERS){
                continue;
            }
            System.out.println("Opponent: " + other.getName() + ", members: " + size);

            String answer = aiService.matchGroupGoals(
                    ourGoal.getTitle(),
                    goal.getTitle()
            );
            String scoreText = aiService.field(answer, "SCORE");
            String reason = aiService.field(answer, "REASON");
            if(reason == null){
                reason = "Similar group goals";
            }

            int score = 0;

            try{
                if(scoreText != null){
                    // the AI may answer "85", "85/100" or "85%": the first number is the score
                    java.util.regex.Matcher number = java.util.regex.Pattern.compile("\\d+").matcher(scoreText);
                    if(number.find()){
                        score = Integer.parseInt(number.group());
                    }
                }
            }catch(NumberFormatException e){
                score = 0;
            }

            score = Math.max(0, Math.min(100, score));
            System.out.println("Match score with " + other.getName() + ": " + score + " (AI: " + scoreText + ")");

            if(score < 65){
                continue;
            }

            // Adjust the score based on weekly commitment difficulty
            int timesDifference = Math.abs(ourGoal.getTimesPerWeek() - goal.getTimesPerWeek());
            score -= timesDifference * 3;

            // Adjust the score based on group size
            int sizeDifference = Math.abs(ourSize - size);
            score -= sizeDifference * 2;

            score = Math.max(0, score);

            if(score < 65){
                continue;
            }

            scores.put(other.getId(), score);

            list.add(new SimilarGroupResponse(
                    other.getId(),
                    other.getName(),
                    size,
                    goal.getTitle(),
                    goal.getProofMethod(),
                    score,
                    reason
            ));
        }

        list.sort((a, b) -> Integer.compare(
                scores.get(b.getGroupId()),
                scores.get(a.getGroupId())
        ));

        return list.size() > 5 ? list.subList(0, 5) : list;
    }

    // by the other group's id (from the suggestions) or its invite code
    @Transactional
    public GroupMatchResponse challenge(Integer groupId, Integer ownerId, Integer opponentGroupId, String opponentInviteCode){
        GroupMember owner = groupAccessService.checkOwner(groupId, ownerId);
        Group opponent = opponentGroupId != null ? groupRepository.findGroupById(opponentGroupId)
                : groupRepository.findGroupByInviteCode(opponentInviteCode);
        if(opponent == null || !"ACTIVE".equals(opponent.getStatus())){
            throw new ApiException("Group not found");
        }
        if(opponent.getId().equals(groupId)){
            throw new ApiException("You cannot challenge your own group");
        }
        if(groupGoalRepository.findGroupGoalByGroupIdAndStatus(groupId, "ACTIVE") == null
                || groupGoalRepository.findGroupGoalByGroupIdAndStatus(opponent.getId(), "ACTIVE") == null){
            throw new ApiException("Both groups need a running goal");
        }
        if(hasOpenMatch(groupId, opponent.getId())){
            throw new ApiException("There is already a match between the two groups");
        }
        // one match at a time: not while we are in a match or waiting for an answer, and not against a group in a match
        if(hasActiveMatch(groupId, null) || hasSentChallenge(groupId)){
            throw new ApiException("Your group already has a match, one match at a time");
        }
        if(hasActiveMatch(opponent.getId(), null)){
            throw new ApiException("The other group is in a match now, try after it ends");
        }
        GroupMatch match = new GroupMatch();
        match.setStatus("PENDING");
        match.setChallengerScore(0);
        match.setOpponentScore(0);
        match.setChallenger(owner.getGroup());
        match.setOpponent(opponent);
        groupMatchRepository.save(match);
        groupAccessService.systemMessage(opponent, owner.getGroup().getName() + " challenged you to a one week match");
        return toResponse(match);
    }

    // the owner of the challenged group accepts or declines, the match is the next full week
    @Transactional
    public GroupMatchResponse respond(Integer matchId, Integer ownerId, boolean accept){
        GroupMatch match = groupMatchRepository.findGroupMatchById(matchId);
        if(match == null || !"PENDING".equals(match.getStatus())){
            throw new ApiException("Match not found");
        }
        groupAccessService.checkOwner(match.getOpponent().getId(), ownerId);
        if(accept && (hasActiveMatch(match.getOpponent().getId(), matchId) || hasActiveMatch(match.getChallenger().getId(), matchId))){
            throw new ApiException("One of the groups is in a match now, one match at a time");
        }
        if(accept){
            LocalDate today = LocalDate.now();
            LocalDate start = today.getDayOfWeek() == DayOfWeek.SUNDAY ? today : today.with(TemporalAdjusters.next(DayOfWeek.SUNDAY));
            match.setStatus("ACTIVE");
            match.setStartDate(start);
            match.setEndDate(start.plusDays(6));
            GroupGoal challengerGoal = groupGoalRepository.findGroupGoalByGroupIdAndStatus(match.getChallenger().getId(), "ACTIVE");
            GroupGoal opponentGoal = groupGoalRepository.findGroupGoalByGroupIdAndStatus(match.getOpponent().getId(), "ACTIVE");

            if(challengerGoal == null || opponentGoal == null){
                throw new ApiException("Both groups must have an active goal");
            }

            if(challengerGoal.getEndDate().isBefore(match.getEndDate()) ||
                    opponentGoal.getEndDate().isBefore(match.getEndDate())){
                throw new ApiException("Both goals must continue until the match ends");
            }

            match.setChallengerGoal(challengerGoal);
            match.setOpponentGoal(opponentGoal);
            groupAccessService.systemMessage(match.getChallenger(), match.getOpponent().getName() + " accepted the match, it starts " + start);
            groupAccessService.systemMessage(match.getOpponent(), "The match with " + match.getChallenger().getName() + " starts " + start);
        }else{
            match.setStatus("DECLINED");
            groupAccessService.systemMessage(match.getChallenger(), match.getOpponent().getName() + " declined the match");
        }
        groupMatchRepository.save(match);
        return toResponse(match);
    }

    public List<GroupMatchResponse> getMatches(Integer groupId, Integer memberId){
        groupAccessService.getActiveMembership(groupId, memberId);
        List<GroupMatchResponse> list = new ArrayList<>();
        for(GroupMatch match : groupMatchRepository.findGroupMatchesByChallengerIdOrOpponentIdOrderByIdDesc(groupId, groupId)){
            list.add(toResponse(match));
        }
        return list;
    }

    // sunday 00:00, before the settlement: score = % of the times done by the group in the match week
    @Transactional
    public void finishMatches(LocalDate sunday){
        LocalDate saturday = sunday.minusDays(1);
        for(GroupMatch match : groupMatchRepository.findGroupMatchesByStatus("ACTIVE")){
            if(match.getEndDate() == null || match.getEndDate().isAfter(saturday)){
                continue;
            }
            List<MemberWeek> challengerWeeks = groupGoalService.closedWeeks(match.getChallengerGoal(), match.getEndDate());
            List<MemberWeek> opponentWeeks = groupGoalService.closedWeeks(match.getOpponentGoal(), match.getEndDate());

            int challengerScore = score(challengerWeeks);
            int opponentScore = score(opponentWeeks);
            match.setChallengerScore(challengerScore);
            match.setOpponentScore(opponentScore);

            if(allDone(challengerWeeks)){
                pointLogService.addGroupPoints(match.getChallenger(), PointLogService.MATCH_ALL_DONE_POINTS, "MATCH_ALL_DONE");
            }
            if(allDone(opponentWeeks)){
                pointLogService.addGroupPoints(match.getOpponent(), PointLogService.MATCH_ALL_DONE_POINTS, "MATCH_ALL_DONE");
            }

            if(challengerScore != opponentScore){
                Group winner = challengerScore > opponentScore ? match.getChallenger() : match.getOpponent();
                match.setWinner(winner);
                pointLogService.addGroupPoints(winner, PointLogService.MATCH_WIN_POINTS, "MATCH_WIN");
            }

            // least procrastinating: on average their proofs came earlier in the week
            double challengerDelay = averageDelay(challengerWeeks);
            double opponentDelay = averageDelay(opponentWeeks);
            if(challengerDelay >= 0 && opponentDelay >= 0 && challengerDelay != opponentDelay){
                Group early = challengerDelay < opponentDelay ? match.getChallenger() : match.getOpponent();
                match.setLeastProcrastinating(early);
                pointLogService.addGroupPoints(early, PointLogService.LEAST_PROCRASTINATION_POINTS, "LEAST_PROCRASTINATION");
            }

            match.setStatus("FINISHED");
            groupMatchRepository.save(match);
            String result = match.getChallenger().getName() + " " + challengerScore + "% - " + opponentScore + "% " + match.getOpponent().getName()
                    + (match.getWinner() == null ? ", a draw" : ", the winner is " + match.getWinner().getName());
            groupAccessService.systemMessage(match.getChallenger(), "Match result: " + result);
            groupAccessService.systemMessage(match.getOpponent(), "Match result: " + result);
        }
    }

    private List<MemberWeek> weeksOf(Group group, LocalDate saturday){
        GroupGoal goal = groupGoalRepository.findGroupGoalByGroupIdAndStatus(group.getId(), "ACTIVE");
        return goal == null ? new ArrayList<>() : groupGoalService.closedWeeks(goal, saturday);
    }

    private int score(List<MemberWeek> weeks){
        int required = 0;
        int done = 0;
        for(MemberWeek w : weeks){
            required += w.week().getRequired();
            done += Math.min(w.week().getRequired(), w.week().getCompleted() + w.week().getExcusedDays());
        }
        return required == 0 ? 0 : done * 100 / required;
    }

    private boolean allDone(List<MemberWeek> weeks){
        if(weeks.isEmpty()){
            return false;
        }
        for(MemberWeek w : weeks){
            if(!Boolean.TRUE.equals(w.week().getIsFullWeek())){
                return false;
            }
        }
        return true;
    }

    // hours from the start of the week to every accepted proof, -1 when there are no proofs
    private double averageDelay(List<MemberWeek> weeks){
        long total = 0;
        int count = 0;
        for(MemberWeek w : weeks){
            if(w.week().getProofs() == null){
                continue;
            }
            for(Proof proof : w.week().getProofs()){
                if("ACCEPTED".equals(proof.getResult()) && proof.getSubmittedAt() != null){
                    total += Duration.between(w.week().getWeekStart(), proof.getSubmittedAt()).toHours();
                    count++;
                }
            }
        }
        return count == 0 ? -1 : (double) total / count;
    }

    // a running match of the group (another one than exceptMatchId)
    private boolean hasActiveMatch(Integer groupId, Integer exceptMatchId){
        for(GroupMatch match : groupMatchRepository.findGroupMatchesByChallengerIdOrOpponentIdOrderByIdDesc(groupId, groupId)){
            if("ACTIVE".equals(match.getStatus()) && !match.getId().equals(exceptMatchId)){
                return true;
            }
        }
        return false;
    }

    // the group challenged another group and waits for the answer
    private boolean hasSentChallenge(Integer groupId){
        for(GroupMatch match : groupMatchRepository.findGroupMatchesByChallengerIdOrOpponentIdOrderByIdDesc(groupId, groupId)){
            if("PENDING".equals(match.getStatus()) && match.getChallenger().getId().equals(groupId)){
                return true;
            }
        }
        return false;
    }

    private boolean hasOpenMatch(Integer groupId, Integer otherId){
        for(GroupMatch match : groupMatchRepository.findGroupMatchesByChallengerIdOrOpponentIdOrderByIdDesc(groupId, groupId)){
            boolean same = match.getChallenger().getId().equals(otherId) || match.getOpponent().getId().equals(otherId);
            if(same && ("PENDING".equals(match.getStatus()) || "ACTIVE".equals(match.getStatus()))){
                return true;
            }
        }
        return false;
    }

    private Set<String> words(String text){
        Set<String> set = new HashSet<>();
        if(text != null){
            for(String word : text.toLowerCase().split("\\s+")){
                if(word.length() > 2){
                    set.add(word);
                }
            }
        }
        return set;
    }

    private GroupMatchResponse toResponse(GroupMatch match){
        return new GroupMatchResponse(match.getId(), match.getStatus(),
                match.getChallenger().getId(), match.getChallenger().getName(),
                match.getOpponent().getId(), match.getOpponent().getName(),
                match.getChallengerScore(), match.getOpponentScore(),
                match.getWinner() == null ? null : match.getWinner().getName(),
                match.getLeastProcrastinating() == null ? null : match.getLeastProcrastinating().getName(),
                match.getStartDate(), match.getEndDate(),
                timesPerWeek(match.getChallenger().getId()), timesPerWeek(match.getOpponent().getId()));
    }

    private Integer timesPerWeek(Integer groupId){
        GroupGoal goal = groupGoalRepository.findGroupGoalByGroupIdAndStatus(groupId, "ACTIVE");
        return goal == null ? null : goal.getTimesPerWeek();
    }
}
