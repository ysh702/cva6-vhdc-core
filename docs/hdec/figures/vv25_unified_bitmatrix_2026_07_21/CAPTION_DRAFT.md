# Figure 3 caption draft

## English manuscript caption

**Fig. 3. Construction of the unified bit-matrix representation for HDC and GF(2) ECC.** HDC operands are partitioned directly into 8×32 layouts. For each 16×16 ECC leaf, the second operand is reversed as \(b_{\mathrm{rev},t}=b_{15-t}\); each \(a_i\) is copied to 16 pair coordinates, and pair \((a_i,b_{\mathrm{rev},t})\) is aligned by the product-diagonal index \(k=i+j=15+i-t\). A fixed bijection then packs the 256 unique \((i,j)\) pairs into \(\mathbf X_A^{(E)}\) and \(\mathbf X_B^{(E)}\). Consequently, for \(\tau\in\{H,E\}\), both workloads expose the same 8×32 operand type and use the same pointwise AND, \(\mathbf Q^{(\tau)}=\mathbf X_A^{(\tau)}\odot\mathbf X_B^{(\tau)}\). The indigo trace follows the 16 copies of \(a_3\) before and after fixed packing; squares and open circles denote binary 1 and 0, respectively.

## 中文释义（不直接放入英文稿）

图3只讲“数据怎样统一”，不讲后续硬件归约。HDC本来就能直接分成8×32；ECC先把 \(B\) 反转，再让每个 \(a_i\) 与16个 \(B_{\mathrm{rev}}\) 位依次配对，并按照斜线编号 \(k\) 对齐。固定重排只改变位置，不增加、删除或重复任何 \((i,j)\) 部分积坐标。最终HDC和ECC都得到同形的两张8×32位矩阵，因此同一个逐位AND无需识别当前任务。
