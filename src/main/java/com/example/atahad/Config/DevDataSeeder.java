package com.example.atahad.Config;

import com.example.atahad.Dto.In.*;
import com.example.atahad.Entity.*;
import com.example.atahad.Repository.*;
import com.example.atahad.Service.*;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.core.annotation.Order;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.core.ConnectionCallback;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;

import java.io.InputStream;
import java.math.BigDecimal;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.sql.ResultSet;
import java.sql.Statement;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.temporal.TemporalAdjusters;
import java.util.*;

// the demo data. seed.reset=true wipes every table on each run, so every run starts the demo from the same place
// on only when seed.enabled=true (application-local.properties has the emails and the password)
//
//  عبدالإله  : a year of finished habits (the achievements map), paid what he owed, one habit this week,
//              owner of «تحسين اللياقة البدنية»
//  صبحية    : owner of «ننهي اختبار الآيلتس», the group that gets the challenge in the demo
//  في       : (seed.main-email) locked with 5 SAR since seed.lock-test.main-since, the bank email after it unlocks her
//  تركي     : the admin, two objections waiting and a donation he can cancel
//  سارة، ريم : test members in both groups
@Slf4j
@Order(1) // before GmailLinkSeeder, which links the main user's Gmail
@Component
@RequiredArgsConstructor
@ConditionalOnProperty(name = "seed.enabled", havingValue = "true")
public class DevDataSeeder implements ApplicationRunner {

    private final JdbcTemplate jdbcTemplate;

    private final MemberService memberService;
    private final AdminService adminService;
    private final HabitService habitService;
    private final GroupService groupService;
    private final GroupMemberService groupMemberService;
    private final GroupGoalService groupGoalService;
    private final ChatMessageService chatMessageService;
    private final CommitmentWeekService commitmentWeekService;
    private final GroupAccessService groupAccessService;
    private final LockService lockService;
    private final WhatsAppService whatsAppService;

    private final UserRepository userRepository;
    private final MemberRepository memberRepository;
    private final AdminRepository adminRepository;
    private final HabitRepository habitRepository;
    private final CommitmentWeekRepository commitmentWeekRepository;
    private final ProofRepository proofRepository;
    private final PointLogRepository pointLogRepository;
    private final PenaltyRepository penaltyRepository;
    private final ExcuseRepository excuseRepository;
    private final ObjectionRepository objectionRepository;
    private final GroupRepository groupRepository;
    private final GroupMemberRepository groupMemberRepository;
    private final GroupGoalRepository groupGoalRepository;
    private final GroupSettlementRepository groupSettlementRepository;
    private final MomentRepository momentRepository;

    @Value("${seed.reset:false}")
    private boolean reset;
    @Value("${seed.main-email}")
    private String mainEmail;
    @Value("${seed.main-phone}")
    private String mainPhone;
    @Value("${seed.password:Atahad123}")
    private String password;
    @Value("${seed.friend-email:abdulelah@atahad.test}")
    private String abdulelahEmail;
    @Value("${seed.subhiyyah-email:faiali052@gmail.com}")
    private String subhiyyahEmail;
    @Value("${seed.admin-email:turki@gmail.com}")
    private String adminEmail;
    @Value("${seed.lock-test.main-since:}")
    private String mainSince; // the main user owes from this time, a bank email after it pays it
    @Value("${seed.demo.whatsapp:true}")
    private boolean whatsapp; // queue the lock message on every run

    private final Random random = new Random(7); // the same "random" year on every run

    @Override
    public void run(ApplicationArguments args) {
        if (reset) {
            wipe();
        } else if (userRepository.findUserByEmail(mainEmail) != null) {
            log.info("Seed: the data is already there, nothing added");
            return;
        }

        // ---------- the users ----------
        Member abdulelah = member("عبدالإله", abdulelahEmail, "+966500000001");
        Member subhiyyah = member("صبحية", subhiyyahEmail, "+966500000002");
        Member fai = member("في", mainEmail, mainPhone);
        Member sara = member("سارة", "sara@atahad.test", "+966500000003");
        Member reem = member("ريم", "reem@atahad.test", "+966500000004");
        adminService.registerAdmin(new AdminRegisterRequest("تركي", adminEmail, "+966500000009", password, "مراجعة الأعذار"));
        Admin turki = adminRepository.findAdminById(userRepository.findUserByEmail(adminEmail).getId());

        LocalDate thisSunday = LocalDate.now().with(TemporalAdjusters.previousOrSame(DayOfWeek.SUNDAY));

        // ---------- عبدالإله: a year of habits, all finished and paid ----------
        LocalDate yearStart = LocalDate.of(LocalDate.now().getYear(), 1, 1).with(TemporalAdjusters.nextOrSame(DayOfWeek.SUNDAY));
        LocalDate aprilEnd = LocalDate.of(LocalDate.now().getYear(), 4, 26);
        LocalDate augustEnd = LocalDate.of(LocalDate.now().getYear(), 8, 2);
        pastHabit(abdulelah, "المشي ٣٠ دقيقة", "PHOTO", 3, "10.00", yearStart, aprilEnd);
        pastHabit(abdulelah, "قراءة ٢٠ صفحة", "QUIZ", 4, "5.00", aprilEnd, augustEnd);
        pastHabit(abdulelah, "تمرين بالبيت", "PHOTO", 3, "10.00", augustEnd, thisSunday);

        // his one habit this week, done once already
        Habit stretch = new Habit();
        stretch.setTitle("تمارين إطالة ١٥ دقيقة");
        stretch.setProofMethod("PHOTO");
        stretch.setTimesPerWeek(3);
        stretch.setBaseAmount(new BigDecimal("10.00"));
        stretch.setPlannedDays(Set.of("SUN", "TUE", "THU"));
        habitService.addHabit(abdulelah.getId(), stretch);
        CommitmentWeek stretchWeek = commitmentWeekService.getCurrentWeek(abdulelah.getId(), stretch.getId());
        proof(stretchWeek, "PHOTO", LocalDateTime.now().minusHours(3), "ACCEPTED", null, "seed");
        commitmentWeekService.recordCompletion(stretchWeek.getId(), null);
        level(abdulelah, "PERSEVERING", 6, 120);

        // ---------- group 1: تحسين اللياقة البدنية (عبدالإله) ----------
        Group fitness = group(abdulelah, "تحسين اللياقة البدنية", "نتمرن ٣ مرات بالأسبوع ونشجّع بعض");
        join(fitness, sara, reem);
        GroupGoalRequest fitnessGoal = new GroupGoalRequest();
        fitnessGoal.setTitle("تمرين ٣٠ دقيقة");
        fitnessGoal.setProofMethod("PHOTO");
        fitnessGoal.setTimesPerWeek(3);
        fitnessGoal.setTotalWeeks(4);
        fitnessGoal.setAmountPerTime(new BigDecimal("10.00"));
        GroupGoal fitnessActive = groupGoalService.createGoal(fitness.getId(), abdulelah.getId(), fitnessGoal);
        // it started last week: the week tab has a summary
        fitnessActive.setStartDate(thisSunday.minusWeeks(1));
        fitnessActive.setEndDate(thisSunday.minusWeeks(1).plusDays(6).plusWeeks(3));
        groupGoalRepository.save(fitnessActive);
        settlement(fitnessActive, thisSunday.minusWeeks(1),
                "أسبوع حلو! سارة خلّصت مراتها قبل الكل، وعبدالإله ما فاته ولا تمرين. ريم فاتتها مرة، الأسبوع هذا نبيها معنا.",
                titles(fitness, "IRON", abdulelah, "ROCKET", sara));
        setTitle(fitness, abdulelah, "IRON", 60);
        setTitle(fitness, sara, "ROCKET", 50);
        setTitle(fitness, reem, null, 20);
        fitness.setPoints(130);
        groupRepository.save(fitness);
        done(fitnessActive, abdulelah, 1);
        done(fitnessActive, sara, 1);

        chat(fitness, abdulelah, "بداية أسبوع جديد، يلا");
        chat(fitness, sara, "خلّصت تمريني اليوم");
        chat(fitness, reem, "أنا بكرة إن شاء الله");
        chat(fitness, abdulelah, "كفو سارة");

        moment(fitness, abdulelah, "fit_walk.jpg", 0, 2);
        moment(fitness, sara, "fit_yoga.jpg", 0, 6);
        moment(fitness, reem, "fit_bike.jpg", 1, 3);
        moment(fitness, abdulelah, "fit_gym.jpg", 2, 5);
        moment(fitness, sara, "fit_watch.jpg", 4, 1);

        // ---------- group 2: ننهي اختبار الآيلتس (صبحية), gets the challenge in the demo ----------
        Group ielts = group(subhiyyah, "ننهي اختبار الآيلتس", "نذاكر للآيلتس مع بعض لين الاختبار");
        join(ielts, sara, reem);
        GroupGoalRequest ieltsGoal = new GroupGoalRequest();
        ieltsGoal.setTitle("مذاكرة آيلتس");
        ieltsGoal.setProofMethod("TIMER");
        ieltsGoal.setTargetMinutes(45);
        ieltsGoal.setTimesPerWeek(4);
        ieltsGoal.setTotalWeeks(6);
        ieltsGoal.setAmountPerTime(new BigDecimal("5.00"));
        GroupGoal ieltsActive = groupGoalService.createGoal(ielts.getId(), subhiyyah.getId(), ieltsGoal);
        done(ieltsActive, subhiyyah, 1);
        ielts.setPoints(60);
        groupRepository.save(ielts);

        chat(ielts, subhiyyah, "اليوم Reading");
        chat(ielts, reem, "تمام، بعد العشا");
        chat(ielts, sara, "أنا خلصت Listening");

        moment(ielts, subhiyyah, "ielts_notes.jpg", 0, 3);
        moment(ielts, sara, "ielts_books.jpg", 1, 2);
        moment(ielts, reem, "ielts_night.jpg", 2, 8);

        Habit vocab = new Habit();
        vocab.setTitle("١٠ كلمات إنجليزي");
        vocab.setProofMethod("QUIZ");
        vocab.setTimesPerWeek(5);
        vocab.setBaseAmount(new BigDecimal("5.00"));
        habitService.addHabit(subhiyyah.getId(), vocab);
        level(subhiyyah, "COMMITTED", 4, 90);

        // ---------- fitness groups the AI can suggest to «تحسين اللياقة البدنية» (3 members, 3 times a week, like it) ----------
        Member noura = member("نورة", "noura@atahad.test", "+966500000011");
        Member hind = member("هند", "hind@atahad.test", "+966500000012");
        Member lama = member("لمى", "lama@atahad.test", "+966500000013");
        Member muneera = member("منيرة", "muneera@atahad.test", "+966500000014");
        Member dana = member("دانة", "dana@atahad.test", "+966500000015");
        Member asma = member("أسماء", "asma@atahad.test", "+966500000016");
        rival(noura, "نمشي كل يوم", "مشي جماعي ونشجّع بعض", "مشي ٣٠ دقيقة", "PHOTO", null, 90, hind, lama);
        rival(muneera, "نادي الصباح", "نروح النادي الصبح قبل الدوام", "تمرين بالنادي ٤٥ دقيقة", "PHOTO", null, 110, dana, hind);
        rival(asma, "جري المساء", "نجري بعد المغرب", "جري ٢٠ دقيقة", "TIMER", 20, 70, lama, dana);

        // ---------- في: locked with 5 SAR, the bank email after mainSince pays it ----------
        Habit walk = new Habit();
        walk.setTitle("المشي اليومي");
        walk.setProofMethod("PHOTO");
        walk.setTimesPerWeek(3);
        walk.setBaseAmount(new BigDecimal("5.00"));
        habitService.addHabit(fai.getId(), walk);
        CommitmentWeek walkWeek = commitmentWeekService.getCurrentWeek(fai.getId(), walk.getId());
        LocalDateTime since = mainSince.isBlank() ? LocalDateTime.now() : LocalDateTime.parse(mainSince.trim());
        penalty(fai, walkWeek, "5.00", "PENDING", since, null);
        lockService.refresh(memberRepository.findMemberById(fai.getId()));
        if (whatsapp) {
            whatsAppService.lockMessage(memberRepository.findMemberById(fai.getId()), walk.getTitle(), 1,
                    new BigDecimal("5.00"), new BigDecimal("5.00"), false);
        }

        // ---------- what the admin finds: two objections and a donation he can cancel ----------
        CommitmentWeek saraWeek = groupGoalService.currentWeek(fitnessActive, sara);
        Proof rejected = proof(saraWeek, "PHOTO", LocalDateTime.now().minusHours(5), "REJECTED",
                "الصورة مظلمة وما يبين فيها التمرين", photoData("fit_gym.jpg"));
        objection(sara, rejected, null, "كنت بالنادي فعلًا، الإضاءة ضعيفة بس", "ما قدر الذكاء يتأكد من التمرين بالصورة");

        CommitmentWeek reemWeek = groupGoalService.currentWeek(ieltsActive, reem);
        Excuse excuse = new Excuse();
        excuse.setType("SICK");
        excuse.setExcuseDate(LocalDate.now());
        excuse.setStatus("REJECTED");
        excuse.setProcessingStatus("FINISHED");
        excuse.setAiAssessment("التقرير ما يوضح التاريخ");
        excuse.setDecidedAt(LocalDateTime.now().minusHours(2));
        excuse.setCommitmentWeek(reemWeek);
        excuseRepository.save(excuse);
        objection(reem, null, excuse, "كنت مريضة والتاريخ مكتوب تحت بالتقرير", "التقرير ما يوضح التاريخ");

        penalty(reem, reemWeek, "10.00", "PENDING", LocalDateTime.now().minusDays(1), null);
        lockService.refresh(memberRepository.findMemberById(reem.getId()));

        level(sara, "COMMITTED", 3, 80);
        level(reem, "BEGINNER", 1, 30);
        log.info("Seed: the demo is ready, every account uses the same password (admin: {})", turki.getId());
    }

    // ---------- wipe ----------

    // every table of this database, emptied (the structure stays)
    private void wipe() {
        jdbcTemplate.execute((ConnectionCallback<Void>) con -> {
            List<String> tables = new ArrayList<>();
            try (ResultSet rs = con.createStatement().executeQuery(
                    "SELECT table_name FROM information_schema.tables WHERE table_schema = DATABASE() AND table_type = 'BASE TABLE'")) {
                while (rs.next()) {
                    tables.add(rs.getString(1));
                }
            }
            try (Statement st = con.createStatement()) {
                st.execute("SET FOREIGN_KEY_CHECKS = 0");
                for (String table : tables) {
                    st.execute("TRUNCATE TABLE `" + table + "`");
                }
                st.execute("SET FOREIGN_KEY_CHECKS = 1");
            }
            return null;
        });
        log.info("Seed: the database was emptied for the demo");
    }

    // ---------- a finished habit with its weeks, proofs and points ----------

    // weeks from start (a Sunday) until end: most weeks full, some miss a time and that donation is paid
    private void pastHabit(Member member, String title, String method, int times, String amount, LocalDate start, LocalDate end) {
        Habit habit = new Habit();
        habit.setTitle(title);
        habit.setProofMethod(method);
        habit.setTimesPerWeek(times);
        habit.setBaseAmount(new BigDecimal(amount));
        habit.setStatus("ENDED");
        habit.setEffectiveFrom(start);
        habit.setStartDate(start);
        habit.setMember(member);
        if ("TIMER".equals(method)) {
            habit.setTargetMinutes(20);
        }
        habitRepository.save(habit);

        int number = 1;
        for (LocalDate sunday = start; sunday.isBefore(end); sunday = sunday.plusWeeks(1)) {
            int done = random.nextInt(10) < 8 ? times : times - 1; // 8 of 10 weeks are full
            CommitmentWeek week = new CommitmentWeek();
            week.setCommitment(habit);
            week.setWeekNumber(number++);
            week.setWeekStart(sunday.atStartOfDay());
            week.setWeekEnd(sunday.plusDays(6).atTime(23, 59, 59));
            week.setRequired(times);
            week.setCompleted(done);
            week.setExcusedDays(0);
            week.setAmountPerDay(habit.getBaseAmount());
            week.setTrackStatus("SETTLED");
            week.setIsFullWeek(done == times);
            week.setStepsSettlementPending(false);
            commitmentWeekRepository.save(week);

            // the days of the proofs: different days of that week, in the evening
            List<Integer> days = new ArrayList<>(List.of(0, 1, 2, 3, 4, 5, 6));
            Collections.shuffle(days, random);
            for (int i = 0; i < done; i++) {
                LocalDateTime at = sunday.plusDays(days.get(i)).atTime(17 + random.nextInt(5), random.nextInt(60));
                proof(week, method, at, "ACCEPTED", null, "seed");
                PointLog log = new PointLog();
                log.setPoints(10);
                log.setReason("TASK_DONE");
                log.setCreatedAt(at);
                log.setMember(member);
                pointLogRepository.save(log);
            }
            if (done < times) {
                LocalDateTime lost = sunday.plusDays(7).atTime(0, 5);
                penalty(member, week, amount, "PAID", lost, lost.plusDays(1).withHour(20));
            }
        }
    }

    private Proof proof(CommitmentWeek week, String type, LocalDateTime at, String result, String reason, String evidence) {
        Proof proof = new Proof();
        proof.setType(type);
        proof.setEvidenceData(evidence);
        proof.setActivityTime(at);
        proof.setSubmittedAt(at.plusMinutes(2));
        proof.setResult(result);
        proof.setProcessingStatus("FINISHED");
        proof.setRejectionReason(reason);
        proof.setDecidedAt(at.plusMinutes(3));
        proof.setCommitmentWeek(week);
        return proofRepository.save(proof);
    }

    private void penalty(Member member, CommitmentWeek week, String amount, String status, LocalDateTime createdAt, LocalDateTime paidAt) {
        Penalty penalty = new Penalty();
        penalty.setAmount(new BigDecimal(amount));
        penalty.setReason("LOST_DAY");
        penalty.setStatus(status);
        penalty.setCreatedAt(createdAt);
        penalty.setPaidAt(paidAt);
        penalty.setMember(member);
        penalty.setCommitmentWeek(week);
        penaltyRepository.save(penalty);
    }

    private void objection(Member member, Proof proof, Excuse excuse, String reason, String aiReason) {
        Objection objection = new Objection();
        objection.setMember(member);
        objection.setProof(proof);
        objection.setExcuse(excuse);
        objection.setReason(reason);
        objection.setAiReason(aiReason);
        objection.setStatus("PENDING");
        objection.setCreatedAt(LocalDateTime.now().minusHours(1));
        objectionRepository.save(objection);
    }

    // a seed photo as a data url, so the admin sees it
    private String photoData(String file) {
        try (InputStream in = new ClassPathResource("seed/moments/" + file).getInputStream()) {
            return "data:image/jpeg;base64," + Base64.getEncoder().encodeToString(in.readAllBytes());
        } catch (Exception e) {
            return "seed";
        }
    }

    // ---------- groups ----------

    private GroupSettlement settlement(GroupGoal goal, LocalDate weekStart, String text, String titles) {
        GroupSettlement settlement = new GroupSettlement();
        settlement.setWeekStart(weekStart);
        settlement.setSettlementText(text);
        settlement.setTitles(titles);
        settlement.setCreatedAt(weekStart.plusDays(7).atTime(0, 5));
        settlement.setGroupGoal(goal);
        return groupSettlementRepository.save(settlement);
    }

    // titles(group, "IRON", sara, "ROCKET", noura) -> "IRON=4;ROCKET=1" (group member ids)
    private String titles(Group group, Object... pairs) {
        StringBuilder text = new StringBuilder();
        for (int i = 0; i < pairs.length; i += 2) {
            Member member = (Member) pairs[i + 1];
            text.append(text.length() == 0 ? "" : ";").append(pairs[i]).append("=")
                    .append(groupAccessService.getActiveMembership(group.getId(), member.getId()).getId());
        }
        return text.toString();
    }

    private void setTitle(Group group, Member member, String title, int points) {
        GroupMember groupMember = groupAccessService.getActiveMembership(group.getId(), member.getId());
        groupMember.setTitle(title);
        groupMember.setPoints(points);
        groupMemberRepository.save(groupMember);
    }

    // a small fitness group with an active goal of 3 times a week, so it can be challenged
    private void rival(Member owner, String name, String description, String title, String method, Integer minutes,
                       int points, Member... members) {
        Group rival = group(owner, name, description);
        join(rival, members);
        GroupGoalRequest goal = new GroupGoalRequest();
        goal.setTitle(title);
        goal.setProofMethod(method);
        goal.setTargetMinutes(minutes);
        goal.setTimesPerWeek(3);
        goal.setTotalWeeks(4);
        goal.setAmountPerTime(new BigDecimal("5.00"));
        GroupGoal active = groupGoalService.createGoal(rival.getId(), owner.getId(), goal);
        done(active, owner, 1);
        rival.setPoints(points);
        groupRepository.save(rival);
    }

    private Group group(Member owner, String name, String description) {
        Integer id = groupService.addGroup(owner.getId(), new GroupCreateRequest(name, description, "SOLO")).getId();
        return groupAccessService.getGroup(id);
    }

    private void join(Group group, Member... members) {
        for (Member m : members) {
            groupMemberService.joinGroup(m.getId(), group.getInviteCode());
        }
    }

    private void done(GroupGoal goal, Member member, int times) {
        for (int i = 0; i < times; i++) {
            commitmentWeekService.recordCompletion(groupGoalService.currentWeek(goal, member).getId(), null);
        }
    }

    private void chat(Group group, Member member, String text) {
        chatMessageService.send(group.getId(), member.getId(), new ChatMessageRequest(text));
    }

    // a photo moment shared with the group, days and hours ago
    private void moment(Group group, Member member, String file, int daysAgo, int hoursAgo) {
        String name = "seed-" + file;
        try (InputStream in = new ClassPathResource("seed/moments/" + file).getInputStream()) {
            Files.createDirectories(MomentService.UPLOADS);
            Files.copy(in, MomentService.UPLOADS.resolve(name), StandardCopyOption.REPLACE_EXISTING);
        } catch (Exception e) {
            log.warn("Seed: the photo {} was not copied", file);
            return;
        }
        Moment moment = new Moment();
        moment.setMediaUrl("/uploads/moments/" + name); // the app puts the server address before it
        moment.setMediaType("PHOTO");
        moment.setVisibility("GROUP");
        moment.setCreatedAt(LocalDateTime.now().minusDays(daysAgo).minusHours(hoursAgo));
        moment.setMember(member);
        moment.setGroup(group);
        momentRepository.save(moment);
    }

    // ---------- members ----------

    private void level(Member member, String level, int weeks, int points) {
        Member saved = memberRepository.findMemberById(member.getId());
        saved.setLevel(level);
        saved.setConsecutiveWeeks(weeks);
        saved.setPoints(points);
        memberRepository.save(saved);
    }

    private Member member(String name, String email, String phone) {
        memberService.registerMember(new MemberRegisterRequest(name, email, phone, password));
        return memberRepository.findMemberById(userRepository.findUserByEmail(email).getId());
    }
}
