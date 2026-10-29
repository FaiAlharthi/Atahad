package com.example.atahad.AI;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import java.util.List;
import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.Mockito.*;

class QuizAIServiceTest {
    @Test void generalScopedPromptIsUsedForNonProgrammingTopics() {
        OpenRouterClient client=mock(OpenRouterClient.class);
        when(client.completeQuiz(anyString(),anyString(),anyString(),anyList(),anyString(),any(java.time.Duration.class))).thenReturn("questions");
        assertEquals("questions",new QuizAIService(client).questions("التغذية المتوازنة",List.of()));
        var instructions=ArgumentCaptor.forClass(String.class);
        verify(client).completeQuiz(eq("text"),instructions.capture(),eq("Task/topic: التغذية المتوازنة"),eq(List.of()),eq(""),eq(QuizAIService.GENERATION_BUDGET));
        assertTrue(instructions.getValue().contains("formal, clear Arabic"));
        assertTrue(instructions.getValue().contains("strictly within that scope"));
        assertTrue(instructions.getValue().contains("plausible misconceptions"));
        assertTrue(instructions.getValue().contains("exactly 3 options"));
        assertTrue(instructions.getValue().contains("TOPIC: UNCLEAR"));
        assertFalse(instructions.getValue().contains("Java"));
    }
    @Test void suppliedPagesUseVisionAndPreserveTheReadabilityContract() {
        OpenRouterClient client=mock(OpenRouterClient.class);
        var images=List.of("data:image/png;base64,TEST_PAGE");
        when(client.completeQuiz(anyString(),anyString(),anyString(),anyList(),anyString(),any(java.time.Duration.class))).thenReturn("READABLE: NO");
        assertEquals("READABLE: NO",new QuizAIService(client).questions("دورة الماء",images));
        verify(client).completeQuiz(eq("vision"),contains("use only their clearly readable content"),eq("Task/topic: دورة الماء"),eq(images),eq(""),eq(QuizAIService.GENERATION_BUDGET));
    }
}
