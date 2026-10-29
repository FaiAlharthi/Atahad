package com.example.atahad.Service;

import com.example.atahad.AI.QuizAIService;
import com.example.atahad.Api.ApiException;
import com.example.atahad.Dto.In.QuizSourceRequest;
import com.example.atahad.Entity.*;
import com.example.atahad.Repository.*;
import jakarta.persistence.*;
import org.junit.jupiter.api.*;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.*;
import org.springframework.data.jpa.repository.config.EnableJpaRepositories;
import org.springframework.jdbc.datasource.DriverManagerDataSource;
import org.springframework.orm.jpa.*;
import org.springframework.orm.jpa.vendor.HibernateJpaVendorAdapter;
import org.springframework.test.context.junit.jupiter.SpringJUnitConfig;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.*;
import javax.sql.DataSource;
import java.time.*;
import java.math.BigDecimal;
import java.util.*;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

@SpringJUnitConfig(ProofFeatureIntegrationTest.Config.class)
@Transactional
class ProofFeatureIntegrationTest {
    @Configuration @EnableTransactionManagement
    @EnableJpaRepositories("com.example.atahad.Repository")
    @Import({AcceptanceGuardService.class,ProofOutcomeService.class,TimerSessionService.class,ProofTime.class,ProofCaptureService.class,QuizService.class})
    static class Config {
        @Bean DataSource dataSource() {
            return new DriverManagerDataSource("jdbc:h2:mem:proof_features;MODE=MySQL;NON_KEYWORDS=USER,GROUP,VALUE,MONTH;DB_CLOSE_DELAY=-1","sa","");
        }
        @Bean LocalContainerEntityManagerFactoryBean entityManagerFactory(DataSource dataSource) {
            var factory=new LocalContainerEntityManagerFactoryBean();
            factory.setDataSource(dataSource); factory.setPackagesToScan("com.example.atahad.Entity");
            factory.setJpaVendorAdapter(new HibernateJpaVendorAdapter());
            factory.setJpaPropertyMap(Map.of("hibernate.hbm2ddl.auto","create-drop","jakarta.persistence.validation.mode","none"));
            return factory;
        }
        @Bean PlatformTransactionManager transactionManager(EntityManagerFactory factory) { return new JpaTransactionManager(factory); }
        @Bean EntityManager entityManager(EntityManagerFactory factory) { return SharedEntityManagerCreator.createSharedEntityManager(factory); }
        @Bean CommitmentWeekService commitmentWeekService() { return mock(CommitmentWeekService.class); }
        @Bean AuthenticatedUserService authenticatedUserService() { return mock(AuthenticatedUserService.class); }
        @Bean QuizAIService quizAIService() { return mock(QuizAIService.class); }
    }
    @PersistenceContext EntityManager em;
    @Autowired ProofOutcomeService outcome;
    @Autowired TimerSessionService timers;
    @Autowired ProofTime time;
    @Autowired CommitmentWeekService counters;
    @Autowired ProofEvidenceRepository evidence;
    @Autowired QuizService quizzes;
    @Autowired QuizAIService quizAI;
    @Autowired ProofCaptureService captures;
    private Proof proof;
    private Integer memberId;
    private static final ZoneId ZONE=ZoneId.of("Asia/Riyadh");
    private static final String QUESTIONS="Q: سؤال واحد\nA) ألف\nB) باء\nC) جيم\nANSWER: A\n"
            +"Q: سؤال اثنين\nA) ألف\nB) باء\nC) جيم\nANSWER: B\n"
            +"Q: سؤال ثلاثة\nA) ألف\nB) باء\nC) جيم\nANSWER: C\n"
            +"Q: سؤال أربعة\nA) ألف\nB) باء\nC) جيم\nANSWER: A\n";

    void at(String local) { ReflectionTestUtils.setField(time,"clock",Clock.fixed(LocalDateTime.parse(local).atZone(ZONE).toInstant(),ZONE)); }
    @BeforeEach void seed() {
        reset(counters,quizAI);
        at("2026-10-24T10:00:00");
        User user=new User();user.setName("Tester");user.setEmail(UUID.randomUUID()+"@example.test");user.setPhone("+966501234567");user.setPassword("test-hash");user.setRole("MEMBER");em.persist(user);
        Member member=new Member();member.setUser(user);em.persist(member);memberId=member.getId();
        Habit habit=new Habit();habit.setTitle("مهمة اختبار");habit.setMember(member);habit.setProofMethod("TIMER");habit.setTimesPerWeek(3);habit.setStatus("ACTIVE");em.persist(habit);
        CommitmentWeek week=new CommitmentWeek();week.setCommitment(habit);week.setWeekNumber(1);week.setRequired(3);week.setWeekStart(LocalDateTime.parse("2026-10-18T00:00:00"));week.setWeekEnd(LocalDateTime.parse("2026-10-24T23:59:59"));em.persist(week);
        proof=new Proof();proof.setType("TIMER");proof.setEvidenceData("Waiting");proof.setResult("PENDING");proof.setProcessingStatus("WAITING");proof.setActivityTime(time.now());proof.setSubmittedAt(time.now());proof.setCommitmentWeek(week);proof.setAttemptDeadline(LocalDateTime.parse("2026-10-25T00:00:00"));em.persist(proof);em.flush();
        outcome.primary(proof,"PENDING","waiting");
    }
    void photos() {
        ProofEvidence item=new ProofEvidence();item.setProof(proof);item.setType("BEFORE_AFTER");item.setCreatedAt(time.now());em.persist(item);em.flush();
    }
    String tinyImage() throws Exception {
        var image=new java.awt.image.BufferedImage(2,2,java.awt.image.BufferedImage.TYPE_INT_RGB);
        var output=new java.io.ByteArrayOutputStream();javax.imageio.ImageIO.write(image,"png",output);
        return "data:image/png;base64,"+Base64.getEncoder().encodeToString(output.toByteArray());
    }
    Integer capturePage() throws Exception {
        Map<String,Object> ticket=captures.start(memberId,"PAGE",proof.getId());
        var input=new com.example.atahad.Dto.In.CaptureUploadRequest();input.setToken((String)ticket.get("token"));input.setImageData(tinyImage());
        captures.upload(memberId,(Integer)ticket.get("captureId"),input);return (Integer)ticket.get("captureId");
    }
    @Test void cameraTicketChecksOwnerAndCannotBeReused() throws Exception {
        Integer id=capturePage();
        assertThrows(org.springframework.security.access.AccessDeniedException.class,()->captures.use(memberId+1,id,"PAGE",proof.getId()));
        captures.use(memberId,id,"PAGE",proof.getId());
        assertThrows(ApiException.class,()->captures.use(memberId,id,"PAGE",proof.getId()));
    }
    @Test void cameraRejectsInvalidImageAndExpiredTicket() {
        Map<String,Object> ticket=captures.start(memberId,"BEFORE",null);
        var input=new com.example.atahad.Dto.In.CaptureUploadRequest();input.setToken((String)ticket.get("token"));input.setImageData("data:image/png;base64,YWJj");
        assertThrows(ApiException.class,()->captures.upload(memberId,(Integer)ticket.get("captureId"),input));
        at("2026-10-24T10:05:00");
        assertThrows(ApiException.class,()->captures.upload(memberId,(Integer)ticket.get("captureId"),input));
    }
    @Test void unreadablePagesRequestOneReuploadThenUseGeneralQuestions() throws Exception {
        proof.setType("QUIZ");proof.getCommitmentWeek().getCommitment().setProofMethod("QUIZ");em.flush();
        when(quizAI.questions(anyString(),anyList(),any(Duration.class))).thenAnswer(call->((List<?>)call.getArgument(1)).isEmpty()?QUESTIONS:"READABLE: NO");
        var input=new QuizSourceRequest();input.setProofId(proof.getId());input.setCaptureIds(List.of(capturePage()));
        var first=quizzes.create(memberId,proof.getCommitmentWeek().getId(),null,null,input);
        assertNull(first.getQuizId());assertTrue(proof.getPageReuploadRequested());
        input.setCaptureIds(List.of(capturePage()));
        var second=quizzes.create(memberId,proof.getCommitmentWeek().getId(),null,null,input);
        assertNotNull(second.getQuizId());assertEquals(4,second.getQuestions().size());
        verify(quizAI).questions(anyString(),eq(List.of()),any(Duration.class));
    }
    @Test void successfulPhotosRescueFailedPrimaryAndCountOnce() {
        photos();outcome.primary(proof,"REJECTED","failed");assertEquals("PENDING",proof.getResult());
        outcome.record(proof,"BEFORE_AFTER","ACCEPTED","visible work");assertEquals("ACCEPTED",proof.getResult());
        outcome.primary(proof,"ACCEPTED","late timer");verify(counters,times(1)).recordCompletion(proof.getCommitmentWeek().getId(),null);
    }
    @Test void rejectedExtraEvidenceDoesNotUndoPrimarySuccess() {
        photos();outcome.primary(proof,"ACCEPTED","timer done");outcome.record(proof,"BEFORE_AFTER","REJECTED","mismatch");
        assertEquals("ACCEPTED",proof.getResult());verify(counters,times(1)).recordCompletion(proof.getCommitmentWeek().getId(),null);
    }
    @Test void uncertainPhotosEscalateOnlyAfterPrimaryFinishes() {
        photos();outcome.record(proof,"BEFORE_AFTER","ESCALATED","uncertain");assertEquals("PENDING",proof.getResult());
        outcome.primary(proof,"REJECTED","failed");assertEquals("ESCALATED",proof.getResult());
        outcome.review(proof,true,"admin accepted");assertEquals("ACCEPTED",proof.getResult());
    }
    @Test void twoFailedEvidenceMethodsRejectTheAttempt() {
        photos();outcome.primary(proof,"REJECTED","failed");outcome.record(proof,"BEFORE_AFTER","REJECTED","failed");assertEquals("REJECTED",proof.getResult());verifyNoInteractions(counters);
    }
    @Test void pauseDoesNotCountBreakAndOptionalExtensionDoesNotCreditTwice() {
        TimerSession timer=timers.start(proof,30,"start\nhalf\nfinish");
        at("2026-10-24T10:10:00");timers.action(memberId,timer.getId(),"pause",null,null);assertEquals(600,timer.getElapsedSeconds());
        at("2026-10-24T11:00:00");timers.action(memberId,timer.getId(),"resume",null,null);
        at("2026-10-24T11:20:00");timers.action(memberId,timer.getId(),"state",null,null);assertEquals(1800,timer.getElapsedSeconds());assertEquals("ACCEPTED",proof.getResult());
        timers.action(memberId,timer.getId(),"extend",5,null);at("2026-10-24T11:22:00");timers.action(memberId,timer.getId(),"finish",null,null);
        timers.action(memberId,timer.getId(),"feedback",null,"TIRING");assertEquals("ACCEPTED",proof.getResult());verify(counters,times(1)).recordCompletion(proof.getCommitmentWeek().getId(),null);
    }
    @Test void sameDayResumeIsAllowedButNoMinutesCarryToTomorrow() {
        at("2026-10-24T23:50:00");TimerSession timer=timers.start(proof,30,"messages");
        at("2026-10-25T00:01:00");timers.action(memberId,timer.getId(),"state",null,null);
        assertEquals(600,timer.getElapsedSeconds());assertEquals("EXPIRED",timer.getStatus());assertEquals("REJECTED",proof.getResult());
        assertThrows(ApiException.class,()->timers.action(memberId,timer.getId(),"resume",null,null));
    }
    @Test void backgroundSessionCompletesEvenIfNextReadIsAfterMidnight() {
        at("2026-10-24T23:00:00");TimerSession timer=timers.start(proof,30,"messages");
        at("2026-10-25T00:01:00");timers.action(memberId,timer.getId(),"state",null,null);
        assertEquals("ACCEPTED",proof.getResult());assertEquals(LocalDateTime.parse("2026-10-24T23:30:00"),timer.getRequiredReachedAt());
    }
    @Test void timerActionsRejectAnotherMember() {
        TimerSession timer=timers.start(proof,30,"messages");
        assertThrows(org.springframework.security.access.AccessDeniedException.class,()->timers.action(memberId+1,timer.getId(),"pause",null,null));
    }
    void quizActivity() { proof.setType("QUIZ");proof.getCommitmentWeek().getCommitment().setProofMethod("QUIZ");em.flush();when(quizAI.questions(anyString(),anyList(),any(Duration.class))).thenReturn(QUESTIONS); }
    QuizSourceRequest quizRequest() { QuizSourceRequest request=new QuizSourceRequest();request.setProofId(proof.getId());return request; }
    @Test void fourQuestionsPassWithThreeAndOnlyOneRetryIsAllowed() {
        quizActivity();var first=quizzes.create(memberId,proof.getCommitmentWeek().getId(),null,null,quizRequest());assertEquals(4,first.getQuestions().size());
        proof.setEvidenceData(first.getQuizId()+":BBBB");assertNotNull(quizzes.grade(proof));assertTrue(quizzes.canRetry(proof));
        var second=quizzes.create(memberId,proof.getCommitmentWeek().getId(),null,null,quizRequest());
        proof.setEvidenceData(second.getQuizId()+":ABCB");assertNull(quizzes.grade(proof));
        assertThrows(ApiException.class,()->quizzes.create(memberId,proof.getCommitmentWeek().getId(),null,null,quizRequest()));
    }
    @Test void quizExpiresAtExactlyOneHourAndRequiresExactlyFourLetters() {
        quizActivity();var quiz=quizzes.create(memberId,proof.getCommitmentWeek().getId(),null,null,quizRequest());
        assertEquals(LocalDateTime.parse("2026-10-24T11:00:00"), quiz.getExpiresAt());
        proof.setEvidenceData(quiz.getQuizId()+":ABC");assertNotNull(quizzes.grade(proof));
        proof.setEvidenceData(quiz.getQuizId()+":ABCA");at("2026-10-24T11:00:00");assertEquals("انتهت صلاحية الساعة",quizzes.grade(proof));
    }
    @Test void providerFailureDoesNotConsumeAQuizAttempt() {
        quizActivity();when(quizAI.questions(anyString(),anyList(),any(Duration.class))).thenReturn("");
        assertThrows(ApiException.class,()->quizzes.create(memberId,proof.getCommitmentWeek().getId(),null,null,quizRequest()));
        assertTrue(quizzes.canRetry(proof));
    }
    @Test void unclearTopicDoesNotConsumeAttemptAndCanBeClarified() {
        quizActivity();when(quizAI.questions(anyString(),anyList(),any(Duration.class))).thenReturn("TOPIC: UNCLEAR");
        var error=assertThrows(ApiException.class,()->quizzes.create(memberId,proof.getCommitmentWeek().getId(),null,null,quizRequest()));
        assertTrue(error.getMessage().contains("Quiz topic is unclear"));assertTrue(quizzes.canRetry(proof));
        when(quizAI.questions(eq("أساسيات التغذية المتوازنة"),anyList(),any(Duration.class))).thenReturn(QUESTIONS);
        var quiz=quizzes.create(memberId,proof.getCommitmentWeek().getId(),null,"أساسيات التغذية المتوازنة",quizRequest());
        assertEquals(1,em.find(Quiz.class,quiz.getQuizId()).getAttemptNumber());
    }
    @Test void duplicateCreateReturnsTheCurrentQuizInsteadOfUsingTheRetry() {
        quizActivity();var first=quizzes.create(memberId,proof.getCommitmentWeek().getId(),null,null,quizRequest());
        var same=quizzes.create(memberId,proof.getCommitmentWeek().getId(),null,null,quizRequest());assertEquals(first.getQuizId(),same.getQuizId());assertEquals(4,same.getQuestions().size());
        assertEquals(first.getExpiresAt(), same.getExpiresAt());
    }
}
