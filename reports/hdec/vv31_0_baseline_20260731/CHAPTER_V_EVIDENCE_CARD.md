# Chapter V Evidence Card: VV31-0 Entry Constraint

1. **Computation object**  
   Background K-233 PMUL and the complete HDC training and inference episode.

2. **Direct-execution constraint**  
   A held-valid HSIM request waits 155427 cycles before acceptance while one
   random background PMUL is active. Once accepted, the same HSIM still
   requires 40 service cycles. The entry resource trace reports no compatible
   HDC/ECC paired event.

3. **Exploitable relation**  
   No relation is accepted at VV31-0.  Candidate compatibility between ECC
   square, ECC operand preparation, local control, and HDC data computation
   remains a hypothesis until simultaneous resource events are demonstrated.

4. **Scheduling method**  
   None at the entry baseline.

5. **Physical change**  
   None.  VV31-0 adds verification and simulation observability only.

6. **Direct evidence**  
   Entry PPA is 4651 Logic LUT, 1274 FF, 4 BRAM, 0 DSP, WNS 0.328 ns at
   5 ns. Four random legal scalars each require 159221 PMUL cycles. A matched
   post-probe synthesis reproduces these values exactly. The diagnostic state
   profile counts 1187 field multiplications, 1167 square writes, 233 scalar
   reads, and 10683 diagonal-launch states.

7. **Applicability boundary**  
   No fine-grained HDC and ECC overlap, 15-cycle foreground wait bound, or
   utilization improvement may be claimed from the entry evidence.
