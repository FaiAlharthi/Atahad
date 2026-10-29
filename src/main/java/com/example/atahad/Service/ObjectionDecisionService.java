package com.example.atahad.Service;

import com.example.atahad.AI.AiService;

import com.example.atahad.Api.ApiException;
import com.example.atahad.Dto.In.ObjectionRequest;
import com.example.atahad.Entity.*;
import com.example.atahad.Repository.MemberRepository;
import com.example.atahad.Repository.ObjectionRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

// an objection on a REJECTED proof, excuse or donation proof (within 48 hours of the decision)
// AI acceptance reverses the old decision; AI rejection or uncertainty stays PENDING for the admin.
@Service
@RequiredArgsConstructor
public class ObjectionDecisionService {
    private final AuthenticatedUserService authenticatedUserService;
    private final ProofAttachmentService proofAttachmentService;
    private final ObjectionRepository objectionRepository;
    private final MemberRepository memberRepository;
    private final ProofDecisionService proofDecisionService;
    private final ExcuseDecisionService excuseDecisionService;
    private final DonationProofService donationProofService;
    private final AiService aiService;

    // the objections on proofs and excuses are added in ObjectionService, the donation ones here
    @Transactional
    public Objection addDonationObjection(Integer memberId, Integer donationProofId, ObjectionRequest request){
        // the id in the path must be the logged in member
        authenticatedUserService.checkMember(memberId);
        Member member = memberRepository.findMemberById(memberId);
        if(member == null){
            throw new ApiException("Member not found");
        }
        DonationProof proof = donationProofService.getProof(donationProofId);
        if(!proof.getMember().getId().equals(memberId)){
            throw new ApiException("This donation proof is not yours");
        }
        if(!"REJECTED".equals(proof.getStatus())){
            throw new ApiException("Only a rejected donation proof can be objected");
        }
        if(proof.getCreatedAt().plusHours(48).isBefore(LocalDateTime.now())){
            throw new ApiException("The 48 hours to object have ended");
        }
        if(objectionRepository.findObjectionByDonationProofId(donationProofId) != null){
            throw new ApiException("This donation proof already has an objection");
        }
        Objection objection = new Objection();
        objection.setReason(request.getReason());
        objection.setStatus("PENDING");
        objection.setCreatedAt(LocalDateTime.now());
        objection.setMember(member);
        objection.setDonationProof(proof);
        objectionRepository.save(objection);
        decide(objection);
        return objection;
    }

    @Transactional
    public void decide(Objection objection){
        String context;
        List<String> images = new ArrayList<>();
        if(objection.getProof() != null){
            Proof proof = objection.getProof();
            context = "Rejected proof of type " + proof.getType() + ", reason of the rejection: " + proof.getRejectionReason()
                    + ("PHOTO".equals(proof.getType()) ? "" : "\nEvidence: " + proof.getEvidenceData());
            if("PHOTO".equals(proof.getType())){
                images.add(proof.getEvidenceData());
            }
        }else if(objection.getExcuse() != null){
            Excuse excuse = objection.getExcuse();
            context = "Rejected excuse of type " + excuse.getType() + " on " + excuse.getExcuseDate()
                    + ", reason of the rejection: " + excuse.getAiAssessment();
            if(excuse.getEvidenceUrl() != null && !excuse.getEvidenceUrl().isBlank()){
                images.add(proofAttachmentService.resolve(objection.getMember().getId(), excuse.getEvidenceUrl()));
            }
        }else{
            DonationProof proof = objection.getDonationProof();
            context = "Rejected donation proof: amount " + proof.getAmount() + ", recipient " + proof.getRecipient()
                    + ", time " + proof.getTransactionTime() + ", reason of the rejection: " + proof.getAiResult();
            if(proof.getBankMessageImageUrl() != null){
                images.add(proofAttachmentService.resolve(objection.getMember().getId(), proof.getBankMessageImageUrl()));
                images.add(proofAttachmentService.resolve(objection.getMember().getId(), proof.getEhsanMessageImageUrl()));
            }
        }

        String answer = aiService.askWithImages(
                "You review objections in a commitment app. A decision was REJECTED and the member objects. "
                        + "Look again at the evidence with his reason. ACCEPTED only when the member is clearly right. "
                        + "ESCALATED when you are not sure. Answer only with two lines:\n"
                        + "DECISION: ACCEPTED or REJECTED or ESCALATED\nREASON: one short sentence in Arabic",
                context + "\n\nThe reason of the member: " + objection.getReason(),
                images,
                "DECISION: ESCALATED\nREASON: الذكاء الاصطناعي غير متاح الحين، بيراجعه الأدمن");

        String decision = aiService.decision(answer);
        objection.setAiReason(cut(aiService.field(answer, "REASON")));
        if(!"ACCEPTED".equals(decision)){
            // AI rejection is advisory: only an admin may finally reject an objection.
            objection.setReviewStartedAt(LocalDateTime.now());
            objectionRepository.save(objection); // stays PENDING for the admin
            return;
        }
        apply(objection, true, null);
    }

    // shared with the admin review
    @Transactional
    public void apply(Objection objection, boolean accept, Admin admin){
        if(!"PENDING".equals(objection.getStatus())){
            throw new ApiException("This objection was already decided");
        }
        objection.setStatus(accept ? "ACCEPTED" : "REJECTED");
        if(admin != null){
            objection.setAdmin(admin);
            objection.setReviewStartedAt(LocalDateTime.now());
        }
        objectionRepository.save(objection);
        if(!accept){
            return;
        }
        if(objection.getProof() != null){
            proofDecisionService.applyDecision(objection.getProof(), "ACCEPTED", "Accepted after the objection");
        }else if(objection.getExcuse() != null){
            excuseDecisionService.applyDecision(objection.getExcuse(), "ACCEPTED", "Accepted after the objection", admin);
        }else if(objection.getDonationProof() != null){
            donationProofService.review(admin, objection.getDonationProof(), true, "Accepted after the objection");
        }
    }

    public List<Objection> getWaitingForAdmin(){
        return objectionRepository.findObjectionsByStatus("PENDING");
    }

    private String cut(String text){
        if(text == null){
            return null;
        }
        return text.length() > 1000 ? text.substring(0, 1000) : text;
    }
}
