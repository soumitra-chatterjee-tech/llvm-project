; Refuse-don't-miscompile: a target object over the launchable VGPR / scratch
; budget must be refused at transpile time rather than emitted to fail at
; dispatch with HSA_STATUS_ERROR_OUT_OF_RESOURCES. The budget is tightened via
; env so an ordinary kernel trips it deterministically; unset, the same kernel
; transpiles.

; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && env HSA_HOTSWAP_MAX_TARGET_VGPR=1 %not %raise_cli %t.hsaco \
; RUN:     --target-isa=gfx942 --write-hsaco=%t.out \
; RUN:     --kernel=target_resource_budget_kernel 2>&1 \
; RUN:   | %FileCheck %s --check-prefix=VGPR

; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && env HSA_HOTSWAP_MAX_TARGET_SCRATCH=0 %not %raise_cli %t.hsaco \
; RUN:     --target-isa=gfx942 --write-hsaco=%t.out \
; RUN:     --kernel=target_resource_budget_kernel 2>&1 \
; RUN:   | %FileCheck %s --check-prefix=SCRATCH

; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx942 --write-hsaco=%t.out \
; RUN:     --kernel=target_resource_budget_kernel 2>&1 \
; RUN:   | %FileCheck %s --check-prefix=OK

; VGPR: target-resource-budget-exceeded
; VGPR-SAME: kernel 'target_resource_budget_kernel'
; VGPR-SAME: target VGPR {{[0-9]+}} exceeds gfx942 max 1

; SCRATCH: target-resource-budget-exceeded
; SCRATCH-SAME: kernel 'target_resource_budget_kernel'
; SCRATCH-SAME: per-lane scratch {{[0-9]+}} B exceeds gfx942 launchable budget 0 B

; OK: raise_cli: wrote
; OK-SAME: target_resource_budget_kernel

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	target_resource_budget_kernel
	.p2align	8
	.type	target_resource_budget_kernel,@function
target_resource_budget_kernel:
	s_load_b64 s[0:1], s[0:1], 0x0
	v_mul_u32_u24_e32 v1, 3, v0
	scratch_store_b32 off, v1, off offset:0
	scratch_load_b32  v1, off, off offset:0
	s_wait_kmcnt 0x0
	global_store_b32 v0, v1, s[0:1] scale_offset
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel target_resource_budget_kernel
		.amdhsa_group_segment_fixed_size 0
		.amdhsa_private_segment_fixed_size 64
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 2
		.amdhsa_next_free_sgpr 2
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 1
		.amdhsa_enable_private_segment 1
	.end_amdhsa_kernel
	.text
	.amdgpu_metadata
---
amdhsa.kernels:
  - .args:
      - { .address_space:  global, .offset:         0, .size:           8, .value_kind:     global_buffer }
    .group_segment_fixed_size: 0
    .kernarg_segment_align: 8
    .kernarg_segment_size: 8
    .max_flat_workgroup_size: 1024
    .name:           target_resource_budget_kernel
    .private_segment_fixed_size: 64
    .sgpr_count:     2
    .symbol:         target_resource_budget_kernel.kd
    .vgpr_count:     2
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
