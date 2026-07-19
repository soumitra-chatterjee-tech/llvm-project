; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --isa=gfx1250 --target-isa=gfx950 \
; RUN:     --emit-ir=ds_swizzle_butterfly_kernel | %FileCheck %s

; Regression guard for the wave-native (wave32 source -> wave64 target)
; ds_swizzle butterfly-reduction stale-partner fix (rocm-systems#159; the
; documented-but-deferred gap P4.b in wave-size-translation.md sec. 10 #3).
;
; A softmax row-max/-sum XOR butterfly stores a per-lane reduction
; accumulator into a VGPR, then reads a *partner* lane's accumulator via a
; convergent `ds_swizzle_b32` (SWAP-N, and_mask=31, within-32-lane). The
; convergent op is emitted OUTSIDE the source-EXEC diamond and runs on all
; 64 hardware lanes, but the accumulator STORE is normally routed through
; the per-lane `emitUnderExec` diamond (`spe_do` -> writeReg -> phi with a
; STALE `spe_skip` arm). At a *partial-EXEC swap site* -- which the real
; gemma `_fwd_kernel` hits at BM16/BN32 -- a source-inactive partner then
; keeps the STALE accumulator instead of the source's data-neutralised
; (`-inf`/`0`) reduction identity, so the active lane's `ds_swizzle` gathers
; a wrong value -> wrong row-max -> empty softmax output (silent
; miscompile).
;
; The fix (`markCrossLaneConsumedDefs` in raiser.cpp + the whole-wave commit
; in `RaiseContext::writeReg32/64`) commits a VGPR def WHOLE-WAVE (skipping
; the `emitUnderExec` diamond) IFF that def's next use is a convergent
; cross-lane primitive under WaveNativeProjection. The computed value is
; already whole-wave-correct (the source masks its data before the swap), so
; the convergent read now sees the correct value on every partner lane.
;
; Discriminator: post-fix, the value feeding `ds_swizzle` is stored
; unconditionally under an artificially-partial EXEC and is NOT guarded by a
; source-EXEC (`spe_do`) diamond immediately before the swizzle. Pre-fix the
; accumulator store sits inside a `spe_do` diamond that produces a phi the
; swizzle then reads (stale on inactive lanes). We assert the accumulator
; write reaches the swizzle with NO intervening `spe_do` diamond.

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	ds_swizzle_butterfly_kernel
	.p2align	8
	.type	ds_swizzle_butterfly_kernel,@function
; CHECK-LABEL: define amdgpu_kernel void @ds_swizzle_butterfly_kernel(
ds_swizzle_butterfly_kernel:
	s_load_b64 s[2:3], s[0:1], 0x0
	; Make EXEC partial: only some lanes active at the swap site. This is
	; the "partial-EXEC swap site" that exposes the stale-partner bug.
	s_mov_b32 exec_lo, 0x0000ffff
	; The butterfly accumulator update -- a whole-wave-computable VALU that
	; writes the VGPR the swizzle will gather cross-lane.
	v_add_f32_e32 v2, v3, v4
	; The convergent cross-lane read of the partner lane's accumulator.
	; Post-fix v2 is committed whole-wave, so the swizzle input is the
	; straight-line fadd result -- there is NO `spe_do` diamond between the
	; accumulator write and this swizzle.
	; CHECK:      %[[ACC:[A-Za-z0-9_.]+]] = fadd float
	; CHECK-NOT:  spe_do
	; CHECK:      call i32 @llvm.amdgcn.ds.swizzle(i32 %{{.*}}, i32 1055)
	ds_swizzle_b32 v5, v2 offset:0x041f
	s_wait_dscnt 0
	; Restore full EXEC and store the swizzled result.
	s_mov_b32 exec_lo, -1
	global_store_b32 v0, v5, s[2:3]
	s_endpgm

	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel ds_swizzle_butterfly_kernel
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 6
		.amdhsa_next_free_sgpr 4
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 1
	.end_amdhsa_kernel

	.text
	.p2alignl 7, 3214868480
	.fill 96, 4, 3214868480
	.text
	.amdgpu_metadata
---
amdhsa.kernels:
  - .args:
      - { .address_space:  global, .offset:         0, .size:           8, .value_kind:     global_buffer }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 8
    .max_flat_workgroup_size: 256
    .name:           ds_swizzle_butterfly_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     4
    .symbol:         ds_swizzle_butterfly_kernel.kd
    .vgpr_count:     6
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
