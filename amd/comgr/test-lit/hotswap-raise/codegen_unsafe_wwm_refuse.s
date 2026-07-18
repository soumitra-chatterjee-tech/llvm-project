; Pre-codegen safety gate: a kernel with more whole-wave-mode (WWM) regions than
; the backend can lower must be refused BEFORE codegen, because the failure mode
; is a SIPreAllocateWWMRegs SIGSEGV during code emission (llvm-project#272,
; backend-owned) that would take down the whole transpile process with no object
; and no error to inspect -- the post-codegen resource-budget gate cannot catch
; it. The WWM budget is tightened via env so a small kernel with one WWM-forcing
; op (ds_swizzle_b32) trips it deterministically; unset, the default budget is
; hundreds of regions and the same kernel transpiles. A real pathological kernel
; (Wan `_10`: 1000 WWM regions) is refused with the default budget on hardware.

; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && env HSA_HOTSWAP_MAX_WWM_REGIONS=0 %not %raise_cli %t.hsaco \
; RUN:     --target-isa=gfx942 --write-hsaco=%t.out \
; RUN:     --kernel=codegen_unsafe_wwm_kernel 2>&1 \
; RUN:   | %FileCheck %s --check-prefix=WWM

; RUN: %llvm_mc -mcpu=gfx1250 %s -o %t.o && %ld_lld -shared %t.o -o %t.hsaco \
; RUN:   && %raise_cli %t.hsaco --target-isa=gfx942 --write-hsaco=%t.out \
; RUN:     --kernel=codegen_unsafe_wwm_kernel 2>&1 \
; RUN:   | %FileCheck %s --check-prefix=OK

; WWM: codegen-unsafe-wwm-pressure
; WWM-SAME: kernel 'codegen_unsafe_wwm_kernel'
; WWM-SAME: WWM-region count {{[0-9]+}} exceeds codegen-safe budget 0

; OK: raise_cli: wrote
; OK-SAME: codegen_unsafe_wwm_kernel

	.amdgcn_target "amdgcn-amd-amdhsa--gfx1250"
	.amdhsa_code_object_version 6
	.text
	.globl	codegen_unsafe_wwm_kernel
	.p2align	8
	.type	codegen_unsafe_wwm_kernel,@function
codegen_unsafe_wwm_kernel:
	s_load_b64 s[0:1], s[0:1], 0x0
	v_mov_b32_e32 v1, v0
	ds_swizzle_b32 v1, v1 offset:0x041f
	s_wait_dscnt 0x0
	global_store_b32 v0, v1, s[0:1] scale_offset
	s_endpgm
	.section	.rodata,"a",@progbits
	.p2align	6, 0x0
	.amdhsa_kernel codegen_unsafe_wwm_kernel
		.amdhsa_group_segment_fixed_size 0
		.amdhsa_private_segment_fixed_size 0
		.amdhsa_kernarg_size 8
		.amdhsa_user_sgpr_count 2
		.amdhsa_user_sgpr_kernarg_segment_ptr 1
		.amdhsa_wavefront_size32 1
		.amdhsa_next_free_vgpr 2
		.amdhsa_next_free_sgpr 2
		.amdhsa_float_denorm_mode_32 3
		.amdhsa_inst_pref_size 1
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
    .name:           codegen_unsafe_wwm_kernel
    .private_segment_fixed_size: 0
    .sgpr_count:     2
    .symbol:         codegen_unsafe_wwm_kernel.kd
    .vgpr_count:     2
    .wavefront_size: 32
amdhsa.version: [1, 2]
...

	.end_amdgpu_metadata
