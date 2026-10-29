package com.example.atahad.Service;

import com.example.atahad.Api.ApiException;
import com.example.atahad.AI.QuizAIService;
import com.example.atahad.Dto.In.QuizSourceRequest;
import com.example.atahad.Dto.Out.*;
import com.example.atahad.Entity.*;
import com.example.atahad.Repository.*;
import jakarta.persistence.EntityManager;
import jakarta.persistence.LockModeType;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import java.time.*;
import java.util.*;
import java.util.regex.*;

@Service @RequiredArgsConstructor
public class QuizService {
    private final AuthenticatedUserService authenticatedUserService;
    private final QuizRepository quizRepository;
    private final CommitmentWeekRepository commitmentWeekRepository;
    private final GoalTaskRepository goalTaskRepository;
    private final ProofCaptureService captures;
    private final ProofRepository proofs;
    private final QuizAIService quizAI;
    private final ProofTime time;
    private final EntityManager entityManager;
    public static final int QUESTIONS=4;
    public static final int TO_PASS=3;
    public static final int VALID_HOURS=1;
    private static final Pattern FORMAT=Pattern.compile("Q:\\s*(.+?)\\s*\\n\\s*A\\)\\s*(.+?)\\s*\\n\\s*B\\)\\s*(.+?)\\s*\\n\\s*C\\)\\s*(.+?)\\s*\\n\\s*ANSWER:\\s*([ABCabc])");

    @Transactional
    public QuizResponse create(Integer memberId,Integer weekId,Integer goalTaskId,String topic) {
        return create(memberId,weekId,goalTaskId,topic,new QuizSourceRequest());
    }

    @Transactional
    public QuizResponse create(Integer memberId,Integer weekId,Integer goalTaskId,String topic,QuizSourceRequest request) {
        authenticatedUserService.checkMember(memberId);
        CommitmentWeek week=commitmentWeekRepository.findCommitmentWeekById(weekId);
        if (week==null || !week.getCommitment().getMember().getId().equals(memberId)) { throw new ApiException("Week not found"); }
        LocalDateTime now=time.now();
        if (now.isBefore(week.getWeekStart()) || now.isAfter(week.getWeekEnd())) { throw new ApiException("This week is not running"); }
        String method=week.getCommitment().getProofMethod();
        String title=week.getCommitment().getTitle();
        GoalTask task=null;
        if (goalTaskId!=null) {
            task=goalTaskRepository.findGoalTaskById(goalTaskId);
            if (task==null || !task.getGoal().getId().equals(week.getCommitment().getId()) || !task.getWeekNumber().equals(week.getWeekNumber())) { throw new ApiException("Task is not in this week"); }
            method=task.getProofMethod(); title+=" - "+task.getTitle();
        }
        if (!method.equals("QUIZ")) { throw new ApiException("This activity does not use a quiz"); }
        Proof proof=null;
        LocalDate day=now.toLocalDate();
        if (request.getProofId()!=null) {
            proof=captures.ownProof(memberId,request.getProofId());
            if (!proof.getCommitmentWeek().getId().equals(weekId) || !sameTask(proof.getGoalTask(),task)) { throw new ApiException("Quiz must match the proof activity"); }
            if (proof.getAttemptDeadline()==null || !now.isBefore(proof.getAttemptDeadline()) || proof.getResult().equals("ACCEPTED")) { throw new ApiException("This proof attempt is closed"); }
            day=proof.getActivityTime().toLocalDate();
        }
        String subject=topic==null || topic.isBlank()?title:topic.trim();
        subject=subject.substring(0,Math.min(200,subject.length()));
        List<Quiz> attempts=attempts(weekId,task,day);
        for (Quiz old:attempts) {
            if (old.getUsedAt()==null && now.isBefore(old.getCreatedAt().plusHours(1))) {
                if (!Objects.equals(old.getProofId(),request.getProofId())) {
                    throw new ApiException("Continue the original quiz attempt before starting another one");
                }
                return response(old);
            }
        }
        if (attempts.size()>=2) { throw new ApiException("Only one retry is allowed for this activity day"); }
        List<String> images=new ArrayList<>();
        if (request.getCaptureIds()!=null && !request.getCaptureIds().isEmpty()) {
            if (proof==null) { throw new ApiException("Start the proof attempt before attaching pages"); }
            for (Integer id:request.getCaptureIds()) { images.add(captures.use(memberId,id,"PAGE",proof.getId()).getImageData()); }
        }
        long generationDeadline = System.nanoTime() + QuizAIService.GENERATION_BUDGET.toNanos();
        String answer=quizAI.questions(subject,images,remainingGenerationTime(generationDeadline));
        if (answer.contains("READABLE: NO")) {
            if (proof==null) { throw new ApiException("Page images are unreadable"); }
            boolean reuploadRequested = proof.getPageReuploadRequested() != null && proof.getPageReuploadRequested();
            if (!reuploadRequested) {
                proof.setPageReuploadRequested(true); proofs.save(proof);
                return new QuizResponse(null,subject,List.of(),"REUPLOAD_PAGES: صوّر الصفحات بوضوح مرة ثانية، ولا تحتسب هذه محاولة اختبار");
            }
            answer=quizAI.questions(subject,List.of(),remainingGenerationTime(generationDeadline));
        }
        if (answer.trim().equals("TOPIC: UNCLEAR")) {
            throw new ApiException("Quiz topic is unclear; specify the activity topic; no quiz attempt was consumed");
        }
        List<QuizQuestionResponse> questions=new ArrayList<>();
        StringBuilder correct=new StringBuilder();
        Matcher matcher=FORMAT.matcher(answer.replace("*",""));
        StringBuilder stored=new StringBuilder();
        while (matcher.find()) {
            questions.add(new QuizQuestionResponse(questions.size()+1,matcher.group(1),List.of("A) "+matcher.group(2),"B) "+matcher.group(3),"C) "+matcher.group(4))));
            correct.append(matcher.group(5).toUpperCase()); stored.append(matcher.group()).append("\n");
        }
        if (questions.size()!=4) { throw new ApiException("Quiz generation is unavailable; no quiz attempt was consumed"); }
        // lock the week after the AI answers, then count the tries again
        entityManager.lock(week,LockModeType.PESSIMISTIC_WRITE);
        if (attempts(weekId,task,day).size()>=2) { throw new ApiException("Only one retry is allowed"); }
        Quiz quiz=new Quiz(); quiz.setTopic(subject); quiz.setQuestions(stored.toString()); quiz.setCorrectAnswers(correct.toString());
        quiz.setCreatedAt(time.now()); quiz.setMember(week.getCommitment().getMember()); quiz.setCommitmentWeek(week); quiz.setGoalTask(task);
        quiz.setProofId(proof==null?null:proof.getId()); quiz.setActivityDate(day); quiz.setAttemptNumber(attempts.size()+1);
        quizRepository.save(quiz);
        return new QuizResponse(quiz.getId(),subject,questions,"أربعة أسئلة، والنجاح من ثلاث إجابات صحيحة.",quiz.getCreatedAt().plusHours(VALID_HOURS));
    }

    @Transactional
    public String grade(Proof proof) {
        Matcher match=Pattern.compile("^\\s*(\\d+)\\s*[:|]\\s*([ABCabc]{4})\\s*$").matcher(proof.getEvidenceData()==null?"":proof.getEvidenceData());
        if (!match.matches()) { return "أرسل أربع إجابات فقط، مثل 12:ABCA"; }
        Quiz quiz=quizRepository.findQuizById(Integer.valueOf(match.group(1)));
        if (quiz==null || !quiz.getCommitmentWeek().getId().equals(proof.getCommitmentWeek().getId()) || !sameTask(quiz.getGoalTask(),proof.getGoalTask())) { return "الاختبار لا يخص هذه المهمة والأسبوع"; }
        if (quiz.getProofId()!=null && !quiz.getProofId().equals(proof.getId())) { return "الاختبار يخص محاولة أخرى"; }
        if (quiz.getActivityDate()!=null && !quiz.getActivityDate().equals(proof.getActivityTime().toLocalDate())) { return "الاختبار لا يخص يوم النشاط"; }
        if (quiz.getUsedAt()!=null) { return "الاختبار مستخدم، اطلب إعادة المحاولة إن كانت متاحة"; }
        if (!time.now().isBefore(quiz.getCreatedAt().plusHours(1))) { return "انتهت صلاحية الساعة"; }
        quiz.setUsedAt(time.now());
        String letters=match.group(2).toUpperCase(); int right=0;
        for (int i=0;i<4;i++) { if (letters.charAt(i)==quiz.getCorrectAnswers().charAt(i)) { right++; } }
        quiz.setScore(right); quizRepository.save(quiz);
        return right>=3?null:"أجبت "+right+" من 4؛ المطلوب 3";
    }
    public boolean canRetry(Proof proof) { return attempts(proof.getCommitmentWeek().getId(),proof.getGoalTask(),proof.getActivityTime().toLocalDate()).size()<2; }
    private List<Quiz> attempts(Integer weekId,GoalTask task,LocalDate day) {
        List<Quiz> list=new ArrayList<>();
        for (Quiz quiz:quizRepository.findByCommitmentWeekIdOrderById(weekId)) {
            LocalDate date=quiz.getActivityDate()==null?quiz.getCreatedAt().toLocalDate():quiz.getActivityDate();
            if (date.equals(day) && sameTask(quiz.getGoalTask(),task)) { list.add(quiz); }
        }
        return list;
    }
    private Duration remainingGenerationTime(long deadline) {
        long remaining = deadline - System.nanoTime();
        if (remaining <= 0) { throw new ApiException("Quiz generation timed out; no quiz attempt was consumed"); }
        return Duration.ofNanos(remaining);
    }
    private boolean sameTask(GoalTask a,GoalTask b) { return a==null?b==null:b!=null && a.getId().equals(b.getId()); }
    private QuizResponse response(Quiz quiz) {
        List<QuizQuestionResponse> list=new ArrayList<>(); Matcher m=FORMAT.matcher(quiz.getQuestions());
        while (m.find()) { list.add(new QuizQuestionResponse(list.size()+1,m.group(1),List.of("A) "+m.group(2),"B) "+m.group(3),"C) "+m.group(4)))); }
        return new QuizResponse(quiz.getId(),quiz.getTopic(),list,"الاختبار الحالي ما زال صالحا؛ النجاح من 3 من 4",quiz.getCreatedAt().plusHours(VALID_HOURS));
    }
}
