package com.example.atahad.Service;

import com.example.atahad.AI.AiService;
import com.example.atahad.Entity.*;
import com.example.atahad.Repository.MemberRepository;
import com.example.atahad.Repository.ObjectionRepository;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import static org.junit.jupiter.api.Assertions.*;
import static org.mockito.ArgumentMatchers.*;
import static org.mockito.Mockito.*;

@ExtendWith(MockitoExtension.class)
class ObjectionDecisionServiceTest {
    @Mock AuthenticatedUserService authenticatedUserService;
    @Mock ProofAttachmentService proofAttachmentService;
    @Mock ObjectionRepository objectionRepository;
    @Mock MemberRepository memberRepository;
    @Mock ProofDecisionService proofDecisionService;
    @Mock ExcuseDecisionService excuseDecisionService;
    @Mock DonationProofService donationProofService;
    @Mock AiService aiService;
    @InjectMocks ObjectionDecisionService decisions;

    private Objection objection(String kind) {
        Objection objection = new Objection();
        objection.setStatus("PENDING");
        objection.setReason("Please review the original evidence with my explanation");
        Member member = new Member(); member.setId(41); objection.setMember(member);
        switch (kind) {
            case "PROOF" -> {
                Proof proof = new Proof(); proof.setType("PHOTO");
                proof.setResult("REJECTED"); proof.setEvidenceData("data:image/png;base64,demo");
                proof.setRejectionReason("Image was unclear"); objection.setProof(proof);
            }
            case "EXCUSE" -> {
                Excuse excuse = new Excuse(); excuse.setType("OTHER");
                excuse.setStatus("REJECTED"); excuse.setAiAssessment("Unclear evidence");
                objection.setExcuse(excuse);
            }
            case "DONATION" -> {
                DonationProof proof = new DonationProof(); proof.setStatus("REJECTED");
                proof.setAiResult("Unclear recipient"); objection.setDonationProof(proof);
            }
        }
        return objection;
    }

    private void aiReturns(String decision) {
        String answer = "DECISION: " + decision + "\nREASON: Needs review";
        when(aiService.askWithImages(anyString(), anyString(), anyList(), anyString())).thenReturn(answer);
        when(aiService.decision(answer)).thenReturn(decision);
        when(aiService.field(answer, "REASON")).thenReturn("Needs review");
    }

    @ParameterizedTest
    @ValueSource(strings = {"PROOF", "EXCUSE", "DONATION"})
    void aiRejectionWaitsForAdminWithoutChangingTheRejectedEvidence(String kind) {
        Objection objection = objection(kind);
        aiReturns("REJECTED");
        decisions.decide(objection);
        assertEquals("PENDING", objection.getStatus());
        assertNotNull(objection.getReviewStartedAt());
        assertEquals("Needs review", objection.getAiReason());
        assertNull(objection.getAdmin());
        verify(objectionRepository).save(objection);
        verifyNoInteractions(proofDecisionService, excuseDecisionService, donationProofService);
    }

    @Test
    void uncertainOrUnavailableAiStillWaitsForAdmin() {
        Objection objection = objection("PROOF");
        aiReturns("ESCALATED");
        decisions.decide(objection);
        assertEquals("PENDING", objection.getStatus());
        assertNotNull(objection.getReviewStartedAt());
        verifyNoInteractions(proofDecisionService, excuseDecisionService, donationProofService);
    }

    @Test
    void clearAiAcceptanceStillAcceptsAndReversesTheProofDecision() {
        Objection objection = objection("PROOF");
        aiReturns("ACCEPTED");
        decisions.decide(objection);
        assertEquals("ACCEPTED", objection.getStatus());
        verify(proofDecisionService).applyDecision(objection.getProof(), "ACCEPTED", "Accepted after the objection");
    }

    @Test
    void adminCanFinallyRejectAfterAiRejection() {
        Objection objection = objection("PROOF");
        aiReturns("REJECTED");
        decisions.decide(objection);
        Admin admin = new Admin();
        decisions.apply(objection, false, admin);
        assertEquals("REJECTED", objection.getStatus());
        assertSame(admin, objection.getAdmin());
        verifyNoInteractions(proofDecisionService, excuseDecisionService, donationProofService);
    }

    @Test
    void adminCanOverrideAiRejectionAndAccept() {
        Objection objection = objection("PROOF");
        aiReturns("REJECTED");
        decisions.decide(objection);
        Admin admin = new Admin();
        decisions.apply(objection, true, admin);
        assertEquals("ACCEPTED", objection.getStatus());
        assertSame(admin, objection.getAdmin());
        verify(proofDecisionService).applyDecision(objection.getProof(), "ACCEPTED", "Accepted after the objection");
    }
}
