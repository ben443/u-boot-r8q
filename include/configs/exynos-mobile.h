/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Samsung Exynos Generic Board Configuration (for mobile devices)
 *
 * Copyright (C) 2025 Kaustabh Chakraborty <kauschluss@disroot.org>
 */

#ifndef __CONFIG_EXYNOS_MOBILE_H
#define __CONFIG_EXYNOS_MOBILE_H

#define CPU_RELEASE_ADDR	secondary_boot_addr
#define CFG_SYS_BAUDRATE_TABLE	{9600, 115200}

/* Enhanced configuration for mainline Linux kernel boot */

/* Kernel boot parameters */
#define CFG_SYS_LOAD_ADDR		0x40000000
#define CFG_SYS_INIT_SP_ADDR		0x45000000

/* Device tree and ramdisk addresses for ARM64 */
#define CFG_SYS_FDT_BASE		0x43000000
#define CFG_SYS_INIT_RAM_ADDR		0x44000000

/* Console configuration */
#define CFG_SYS_CBSIZE			512
#define CFG_SYS_MAXARGS			64

#endif /* __CONFIG_EXYNOS_MOBILE_H */
