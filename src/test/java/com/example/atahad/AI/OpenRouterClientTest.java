package com.example.atahad.AI;

import com.sun.net.httpserver.HttpServer;
import org.junit.jupiter.api.Test;
import org.springframework.test.util.ReflectionTestUtils;
import tools.jackson.databind.ObjectMapper;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.concurrent.CopyOnWriteArrayList;
import static org.junit.jupiter.api.Assertions.*;

class OpenRouterClientTest {
    private static final String DECISION_PROMPT = "Return DECISION: ACCEPTED or REJECTED or ESCALATED, then REASON: an Arabic reason";
    private static final String QUIZ_PROMPT = "Return 4 questions: Q: question A) option B) option C) option ANSWER: A";
    private static final String ACCEPT = "DECISION: ACCEPTED\nREASON: الدليل مطابق";
    private static final String REJECT = "DECISION: REJECTED\nREASON: الدليل لا يطابق المهمة";
    private static final String UNCERTAIN = "DECISION: ESCALATED\nREASON: لم أتمكن من حسم الدليل";
    private static final String QUIZ = ("Q: سؤال\nA) أول\nB) ثاني\nC) ثالث\nANSWER: A\n").repeat(4);

    OpenRouterClient client(Server server) {
        var client = new OpenRouterClient();
        ReflectionTestUtils.setField(client, "apiKey", "test-local-key");
        ReflectionTestUtils.setField(client, "url", server.url());
        for (String purpose : List.of("text", "vision", "timer")) {
            ReflectionTestUtils.setField(client, purpose + "Model", "test/" + purpose + ":free");
            ReflectionTestUtils.setField(client, purpose + "Fallbacks", "test/second:free,test/third:free");
        }
        return client;
    }

    @Test void rateLimitedPrimaryMovesToSecondAndStopsAtAcceptance() throws Exception {
        try (var server = new Server(new Reply(429, ""), new Reply(200, ACCEPT))) {
            assertEquals(ACCEPT, client(server).complete("vision", DECISION_PROMPT, "task", List.of(), "fallback"));
            assertEquals(List.of("test/vision:free", "test/second:free"), server.models());
        }
    }

    @Test void emptyOrMalformedResponsesMoveOnInsteadOfSendingToAdmin() throws Exception {
        try (var server = new Server(new Reply(200, ""), new Reply(200, "not a decision"), new Reply(200, ACCEPT))) {
            assertEquals(ACCEPT, client(server).complete("vision", DECISION_PROMPT, "task", List.of(), "ESCALATED"));
            assertEquals(3, server.requests.size());
        }
    }

    @Test void inconclusiveAnalysisFromFirstTwoModelsStillAllowsThirdToDecide() throws Exception {
        try (var server = new Server(new Reply(200, UNCERTAIN), new Reply(200, UNCERTAIN), new Reply(200, ACCEPT))) {
            assertEquals(ACCEPT, client(server).complete("vision", DECISION_PROMPT, "task", List.of(), "fallback"));
            assertEquals(3, server.requests.size());
        }
    }

    @Test void conclusiveRejectionStopsWithoutShoppingForAcceptance() throws Exception {
        try (var server = new Server(new Reply(200, REJECT), new Reply(200, ACCEPT))) {
            assertEquals(REJECT, client(server).complete("vision", DECISION_PROMPT, "task", List.of(), "fallback"));
            assertEquals(1, server.requests.size());
        }
    }

    @Test void allInconclusiveResultsReachAdminOnlyAfterThreeAttempts() throws Exception {
        try (var server = new Server(new Reply(200, UNCERTAIN))) {
            assertEquals(UNCERTAIN, client(server).complete("vision", DECISION_PROMPT, "task", List.of(), "fallback"));
            assertEquals(3, server.requests.size());
        }
    }

    @Test void allFailedRequestsUseSafeFallbackOnlyAfterThreeAttempts() throws Exception {
        try (var server = new Server(new Reply(429, ""), new Reply(503, ""), new Reply(200, ""))) {
            assertEquals("ESCALATED", client(server).complete("vision", DECISION_PROMPT, "task", List.of(), "ESCALATED"));
            assertEquals(3, server.requests.size());
        }
    }

    @Test void imagesAndBeforeAfterOrderArePreservedForEveryVisionAttempt() throws Exception {
        try (var server = new Server(new Reply(429, ""), new Reply(200, ACCEPT))) {
            var images = List.of("data:image/png;base64,BEFORE", "data:image/png;base64,AFTER");
            assertEquals(ACCEPT, client(server).complete("text", DECISION_PROMPT, "task", images, "fallback"));
            assertEquals(List.of("test/vision:free", "test/second:free"), server.models());
            for (var body : server.requests) {
                var parts = (List<?>) ((Map<?, ?>) ((List<?>) body.get("messages")).get(1)).get("content");
                assertEquals("data:image/png;base64,BEFORE", ((Map<?, ?>) ((Map<?, ?>) parts.get(1)).get("image_url")).get("url"));
                assertEquals("data:image/png;base64,AFTER", ((Map<?, ?>) ((Map<?, ?>) parts.get(2)).get("image_url")).get("url"));
            }
        }
    }

    @Test void missingKeysAndPaidPrimaryModelsNeverMakeRequests() throws Exception {
        try (var server = new Server(new Reply(200, ACCEPT))) {
            var client = client(server);
            ReflectionTestUtils.setField(client, "textModel", "paid/model");
            assertEquals("fallback", client.complete("text", DECISION_PROMPT, "task", List.of(), "fallback"));
            ReflectionTestUtils.setField(client, "apiKey", "");
            assertEquals("fallback", client.complete("vision", DECISION_PROMPT, "task", List.of(), "fallback"));
            assertTrue(server.requests.isEmpty());
        }
    }

    @Test void paidAlternativesAndDuplicatesAreRemovedAndAttemptsAreCappedAtThree() throws Exception {
        try (var server = new Server(new Reply(429, ""))) {
            var client = client(server);
            ReflectionTestUtils.setField(client, "textFallbacks", "paid/model,test/text:free,test/second:free,test/third:free,test/fourth:free");
            assertEquals("fallback", client.complete("text", DECISION_PROMPT, "task", List.of(), "fallback"));
            assertEquals(List.of("test/text:free", "test/second:free", "test/third:free"), server.models());
        }
    }

    @Test void unreadablePagesTryAnotherModelBeforeAskingForNewImages() throws Exception {
        try (var server = new Server(new Reply(200, "READABLE: NO"), new Reply(200, QUIZ))) {
            assertEquals(QUIZ.trim(), client(server).complete("vision", QUIZ_PROMPT, "task", List.of(), ""));
            assertEquals(2, server.requests.size());
        }
        try (var server = new Server(new Reply(200, "READABLE: NO"))) {
            assertEquals("READABLE: NO", client(server).complete("vision", QUIZ_PROMPT, "task", List.of(), ""));
            assertEquals(3, server.requests.size());
        }
    }

    @Test void invalidQuizFormatTriesNextModelBeforeFailingGeneration() throws Exception {
        try (var server = new Server(new Reply(200, "أسئلة بصيغة غير صحيحة"), new Reply(200, QUIZ))) {
            assertEquals(QUIZ.trim(), client(server).complete("text", QUIZ_PROMPT, "task", List.of(), ""));
            assertEquals(2, server.requests.size());
        }
    }

    @Test void unclearTopicTriesAlternativesAndPreservesTheClarificationSignal() throws Exception {
        try(var server=new Server(new Reply(200,"TOPIC: UNCLEAR"),new Reply(200,QUIZ))) {
            assertEquals(QUIZ.trim(),client(server).complete("text",QUIZ_PROMPT,"topic",List.of(),""));
            assertEquals(2,server.requests.size());
        }
        try(var server=new Server(new Reply(200,"TOPIC: UNCLEAR"))) {
            assertEquals("TOPIC: UNCLEAR",client(server).complete("text",QUIZ_PROMPT,"topic",List.of(),""));
            assertEquals(3,server.requests.size());
        }
    }

    @Test void timerUsesItsOwnChain() throws Exception {
        try (var server = new Server(new Reply(429, ""), new Reply(200, "رسالة تشجيعية"))) {
            assertEquals("رسالة تشجيعية", client(server).complete("timer", "encourage", "task", List.of(), "fallback"));
            assertEquals(List.of("test/timer:free", "test/second:free"), server.models());
        }
    }

    @Test void diagnosticsDoNotLogSecretsImagesOrUserText() throws Exception {
        var logger = (ch.qos.logback.classic.Logger) org.slf4j.LoggerFactory.getLogger(OpenRouterClient.class);
        var logs = new ch.qos.logback.core.read.ListAppender<ch.qos.logback.classic.spi.ILoggingEvent>();
        logs.start(); logger.addAppender(logs);
        try (var server = new Server(new Reply(200, ""))) {
            assertEquals("ESCALATED", client(server).complete("vision", DECISION_PROMPT + " PRIVATE_INSTRUCTIONS", "PRIVATE_TASK",
                    List.of("data:image/png;base64,PRIVATE_IMAGE"), "ESCALATED"));
            String text = logs.list.stream().map(e -> e.getFormattedMessage()).collect(java.util.stream.Collectors.joining("\n"));
            assertTrue(text.contains("attempt=3/3"));
            assertTrue(text.contains("exhausted 3 models"));
            for (String secret : List.of("test-local-key", "PRIVATE_INSTRUCTIONS", "PRIVATE_TASK", "PRIVATE_IMAGE")) {
                assertFalse(text.contains(secret));
            }
        } finally { logger.detachAppender(logs); logs.stop(); }
    }

    @Test void quizTotalDeadlineEndsSlowRequestWithoutStartingAnotherModel() throws Exception {
        try (var server = new Server(new Reply(200, QUIZ, 1800))) {
            long start = System.nanoTime();
            var error = assertThrows(com.example.atahad.Api.ApiException.class, () ->
                client(server).completeQuiz("text", QUIZ_PROMPT, "topic", List.of(), "", java.time.Duration.ofMillis(700)));
            assertTrue(error.getMessage().contains("timed out"));
            assertTrue((System.nanoTime() - start) / 1_000_000 < 1700);
            assertEquals(1, server.requests.size());
        }
    }

    @Test void quizHasItsOwnModelAndReasoningSettingsWithoutChangingProofs() throws Exception {
        try (var server = new Server(new Reply(200, QUIZ), new Reply(200, ACCEPT))) {
            var client = client(server);
            ReflectionTestUtils.setField(client, "quizTextModel", "test/quiz:free");
            assertEquals(QUIZ.trim(), client.completeQuiz("text", QUIZ_PROMPT, "topic", List.of(), "", java.time.Duration.ofSeconds(5)));
            assertEquals(ACCEPT, client.complete("vision", DECISION_PROMPT, "photo", List.of(), "fallback"));
            assertEquals(List.of("test/quiz:free", "test/vision:free"), server.models());
            assertEquals(Map.of("effort", "none", "exclude", true), server.requests.get(0).get("reasoning"));
            assertFalse(server.requests.get(1).containsKey("reasoning"));
        }
    }

    @Test void exhaustedQuizBudgetDoesNotMakeAnyRequest() throws Exception {
        try (var server = new Server(new Reply(200, QUIZ))) {
            assertThrows(com.example.atahad.Api.ApiException.class, () ->
                client(server).completeQuiz("text", QUIZ_PROMPT, "topic", List.of(), "", java.time.Duration.ZERO));
            assertTrue(server.requests.isEmpty());
        }
    }

    private record Reply(int status, String content, long delayMillis) {
        Reply(int status, String content) { this(status, content, 0); }
    }
    private static class Server implements AutoCloseable {
        final List<Map<?, ?>> requests = new CopyOnWriteArrayList<>();
        final HttpServer server;
        Server(Reply... replies) throws Exception {
            server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
            server.createContext("/chat", exchange -> {
                var body = new ObjectMapper().readValue(exchange.getRequestBody().readAllBytes(), Map.class);
                int index = requests.size(); requests.add(body);
                Reply reply = replies[Math.min(index, replies.length - 1)];
                String result = reply.status() == 200
                        ? new ObjectMapper().writeValueAsString(Map.of("model", body.get("model"), "choices", List.of(Map.of("message", Map.of("content", reply.content())))))
                        : "{\"error\":{\"message\":\"Unavailable\"}}";
                if (reply.delayMillis() > 0) {
                    try { Thread.sleep(reply.delayMillis()); }
                    catch (InterruptedException interrupted) { Thread.currentThread().interrupt(); }
                }
                byte[] response = result.getBytes(StandardCharsets.UTF_8);
                exchange.getResponseHeaders().add("Content-Type", "application/json");
                exchange.sendResponseHeaders(reply.status(), response.length);
                exchange.getResponseBody().write(response); exchange.close();
            }); server.start();
        }
        String url() { return "http://127.0.0.1:" + server.getAddress().getPort() + "/chat"; }
        List<String> models() { return requests.stream().map(r -> (String) r.get("model")).toList(); }
        public void close() { server.stop(0); }
    }
}
