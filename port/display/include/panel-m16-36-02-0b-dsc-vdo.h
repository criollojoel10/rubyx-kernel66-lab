/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Xiaomi m16 36-02-0b (DSC VDO) - timings transplanted from ruby 4.19
 * panel-m16-36-02-0b-dsc-vdo.c
 */
#ifndef PANEL_M16_36_02_0B_DSC_VDO_H
#define PANEL_M16_36_02_0B_DSC_VDO_H

#define REGFLAG_DELAY           0xFFFC
#define REGFLAG_UDELAY          0xFFFB
#define REGFLAG_END_OF_TABLE    0xFFFD
#define REGFLAG_RESET_LOW       0xFFFE
#define REGFLAG_RESET_HIGH      0xFFFF

#define FRAME_WIDTH                 1080
#define FRAME_HEIGHT                2400
#define PHYSICAL_WIDTH              69552
#define PHYSICAL_HEIGHT             154560
#define DATA_RATE                   831

#define HSA                         8
#define HBP                         16
#define VSA                         4
#define VBP                         8

/* mode 0: 60 Hz */
#define MODE_0_FPS                  60
#define MODE_0_VFP                  2452
#define MODE_0_HFP                  20
/* mode 1: 90 Hz */
#define MODE_1_FPS                  90
#define MODE_1_VFP                  780
#define MODE_1_HFP                  28

/* DSC (ruby) */
#define DSC_ENABLE
#define DSC_VER                     17
#define DSC_SLICE_MODE              1
#define DSC_RGB_SWAP                0
#define DSC_DSC_CFG                 34
#define DSC_RCT_ON                  1
#define DSC_BIT_PER_CHANNEL         8
#define DSC_DSC_LINE_BUF_DEPTH      9
#define DSC_BP_ENABLE               1
#define DSC_BIT_PER_PIXEL           128
#define DSC_SLICE_HEIGHT            20
#define DSC_SLICE_WIDTH             540
#define DSC_CHUNK_SIZE              540
#define DSC_XMIT_DELAY              512
#define DSC_DEC_DELAY               526
#define DSC_SCALE_VALUE             32
#define DSC_INCREMENT_INTERVAL      488
#define DSC_DECREMENT_INTERVAL      7
#define DSC_LINE_BPG_OFFSET         12
#define DSC_NFL_BPG_OFFSET          1294
#define DSC_SLICE_BPG_OFFSET        1302
#define DSC_INITIAL_OFFSET          6144
#define DSC_FINAL_OFFSET            4336
#define DSC_FLATNESS_MINQP          3
#define DSC_FLATNESS_MAXQP          12
#define DSC_RC_MODEL_SIZE           8192
#define DSC_RC_EDGE_FACTOR          6
#define DSC_RC_QUANT_INCR_LIMIT0    11
#define DSC_RC_QUANT_INCR_LIMIT1    11
#define DSC_RC_TGT_OFFSET_HI        3
#define DSC_RC_TGT_OFFSET_LO        3

#define MAX_BRIGHTNESS_CLONE        16383

#endif /* PANEL_M16_36_02_0B_DSC_VDO_H */
