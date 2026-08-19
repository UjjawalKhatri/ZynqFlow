/*
 * main.c — ZynqFlow StreamOps DMA Accelerator Driver & Benchmark
 * Hardware Platform: Digilent ZedBoard (Zynq-7020)
 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "xil_printf.h"
#include "xaxidma.h"
#include "xparameters.h"
#include "xil_cache.h"
#include "xstatus.h"
#include "xil_types.h"
#include "xil_io.h"
#include "xtime_l.h"

#define DMA_DEV_ID          XPAR_AXIDMA_0_DEVICE_ID
#define TX_BUFFER_BASE      0x01000000
#define RX_BUFFER_BASE      0x01200000
#define TEST_BUF_LEN        (64 * 1024)
#define BENCH_BUF_LEN       (1024 * 1024)

#define STREAMOPS_BASE      0x40000000
#define STREAMOPS_CTRL      (STREAMOPS_BASE + 0x00)
#define STREAMOPS_MODE      (STREAMOPS_BASE + 0x04)
#define STREAMOPS_IMM8      (STREAMOPS_BASE + 0x08)
#define STREAMOPS_CLAMP     (STREAMOPS_BASE + 0x0C)
#define STREAMOPS_STATUS    (STREAMOPS_BASE + 0x10)
#define STREAMOPS_IN_BEATS  (STREAMOPS_BASE + 0x14)
#define STREAMOPS_OUT_BEATS (STREAMOPS_BASE + 0x18)
#define STREAMOPS_STALL_CYC (STREAMOPS_BASE + 0x1C)
#define STREAMOPS_FRAMES    (STREAMOPS_BASE + 0x20)
#define STREAMOPS_ACT_CYC   (STREAMOPS_BASE + 0x24)
#define STREAMOPS_VER       (STREAMOPS_BASE + 0x28)

typedef enum {
    OP_BYPASS    = 0,
    OP_RELU      = 1,
    OP_ADD_SAT   = 2,
    OP_CLAMP     = 3,
    OP_ABS       = 4,
    OP_THRESHOLD = 5,
    OP_XOR       = 6,
    OP_RESERVED  = 7
} streamops_mode_t;

static XAxiDma AxiDma;

static inline int8_t sat_add_i8(int8_t a, int8_t b) {
    int16_t res = (int16_t)a + (int16_t)b;
    if (res > 127) return 127;
    if (res < -128) return -128;
    return (int8_t)res;
}

static inline int8_t sat_abs_i8(int8_t a) {
    if (a == -128) return 127;
    return (a < 0) ? -a : a;
}

static void golden_model(const int8_t *src, int8_t *dst, u32 len,
                         streamops_mode_t mode, int8_t imm8,
                         int8_t clamp_lo, int8_t clamp_hi) {
    u32 i;
    for (i = 0; i < len; i++) {
        int8_t val = src[i];
        switch (mode) {
            case OP_BYPASS:
            case OP_RESERVED:
                dst[i] = val;
                break;
            case OP_RELU:
                dst[i] = (val < 0) ? 0 : val;
                break;
            case OP_ADD_SAT:
                dst[i] = sat_add_i8(val, imm8);
                break;
            case OP_CLAMP:
                if (val < clamp_lo) dst[i] = clamp_lo;
                else if (val > clamp_hi) dst[i] = clamp_hi;
                else dst[i] = val;
                break;
            case OP_ABS:
                dst[i] = sat_abs_i8(val);
                break;
            case OP_THRESHOLD:
                dst[i] = (val >= imm8) ? 127 : 0;
                break;
            case OP_XOR:
                dst[i] = val ^ imm8;
                break;
            default:
                dst[i] = val;
                break;
        }
    }
}

static int run_hw_op(u32 len) {
    int status;
    u8 *tx_buf = (u8 *)TX_BUFFER_BASE;
    u8 *rx_buf = (u8 *)RX_BUFFER_BASE;
    u32 timeout;

    XAxiDma_Reset(&AxiDma);
    timeout = 10000;
    while (!XAxiDma_ResetIsDone(&AxiDma)) {
        if (--timeout == 0) return XST_FAILURE;
    }
    XAxiDma_IntrDisable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DMA_TO_DEVICE);
    XAxiDma_IntrDisable(&AxiDma, XAXIDMA_IRQ_ALL_MASK, XAXIDMA_DEVICE_TO_DMA);

    Xil_DCacheFlushRange((UINTPTR)tx_buf, len);
    Xil_DCacheFlushRange((UINTPTR)rx_buf, len);

    status = XAxiDma_SimpleTransfer(&AxiDma, (UINTPTR)rx_buf, len, XAXIDMA_DEVICE_TO_DMA);
    if (status != XST_SUCCESS) return status;

    status = XAxiDma_SimpleTransfer(&AxiDma, (UINTPTR)tx_buf, len, XAXIDMA_DMA_TO_DEVICE);
    if (status != XST_SUCCESS) return status;

    while (XAxiDma_Busy(&AxiDma, XAXIDMA_DMA_TO_DEVICE));
    while (XAxiDma_Busy(&AxiDma, XAXIDMA_DEVICE_TO_DMA));

    Xil_DCacheInvalidateRange((UINTPTR)rx_buf, len);
    return XST_SUCCESS;
}

int main(void) {
    XAxiDma_Config *cfg;
    int status;
    u32 i;
    int8_t *tx_buf = (int8_t *)TX_BUFFER_BASE;
    int8_t *rx_buf = (int8_t *)RX_BUFFER_BASE;
    static int8_t golden_buf[BENCH_BUF_LEN];

    xil_printf("\r\n============================================================\r\n");
    xil_printf("[STREAMOPS] ZynqFlow Hardware Accelerator Test & Benchmark\r\n");
    xil_printf("============================================================\r\n");

    cfg = XAxiDma_LookupConfig(DMA_DEV_ID);
    if (!cfg || XAxiDma_CfgInitialize(&AxiDma, cfg) != XST_SUCCESS) {
        xil_printf("[FAIL] DMA Initialization\r\n");
        return XST_FAILURE;
    }

    u32 ver = Xil_In32(STREAMOPS_VER);
    xil_printf("[INFO] StreamOps Version: 0x%08lx\r\n", ver);
    if (ver != 0x00010000) {
        xil_printf("[FAIL] Invalid StreamOps IP Version!\r\n");
        return XST_FAILURE;
    }

    for (i = 0; i < BENCH_BUF_LEN; i++) {
        tx_buf[i] = (int8_t)((i * 17 + 5) & 0xFF);
    }

    const char *op_names[] = {
        "BYPASS", "RELU", "ADD_SAT (+25)", "CLAMP [-50, 50]",
        "ABS", "THRESHOLD (>= 10)", "XOR (0x55)"
    };
    streamops_mode_t modes[] = {
        OP_BYPASS, OP_RELU, OP_ADD_SAT, OP_CLAMP,
        OP_ABS, OP_THRESHOLD, OP_XOR
    };
    int8_t imm8_vals[] = {0, 0, 25, 0, 0, 10, 0x55};
    int8_t clamp_los[] = {0, 0, 0, -50, 0, 0, 0};
    int8_t clamp_his[] = {0, 0, 0, 50, 0, 0, 0};

    xil_printf("\r\n--- Part 1: Hardware vs C Golden Model Math Verification ---\r\n");

    int total_failures = 0;

    for (int op = 0; op < 7; op++) {
        Xil_Out32(STREAMOPS_MODE, modes[op]);
        Xil_Out32(STREAMOPS_IMM8, (u32)(uint8_t)imm8_vals[op]);
        u32 clamp_reg = ((u32)(uint8_t)clamp_his[op] << 8) | ((u32)(uint8_t)clamp_los[op]);
        Xil_Out32(STREAMOPS_CLAMP, clamp_reg);
        Xil_Out32(STREAMOPS_CTRL, 0x00000003);

        golden_model(tx_buf, golden_buf, TEST_BUF_LEN, modes[op],
                     imm8_vals[op], clamp_los[op], clamp_his[op]);

        status = run_hw_op(TEST_BUF_LEN);
        if (status != XST_SUCCESS) {
            xil_printf("[FAIL] DMA transfer failed for %s\r\n", op_names[op]);
            total_failures++;
            continue;
        }

        int mismatches = 0;
        for (i = 0; i < TEST_BUF_LEN; i++) {
            if (rx_buf[i] != golden_buf[i]) {
                if (mismatches == 0) {
                    xil_printf("  Mismatch at idx %lu: HW=0x%02x, Expected=0x%02x\r\n",
                               i, (uint8_t)rx_buf[i], (uint8_t)golden_buf[i]);
                }
                mismatches++;
            }
        }

        if (mismatches == 0) {
            u32 in_b = Xil_In32(STREAMOPS_IN_BEATS);
            u32 out_b = Xil_In32(STREAMOPS_OUT_BEATS);
            xil_printf("[PASS] %-20s (Beats In/Out: %lu/%lu)\r\n", op_names[op], in_b, out_b);
        } else {
            xil_printf("[FAIL] %-20s Mismatches: %d\r\n", op_names[op], mismatches);
            total_failures++;
        }
    }

    xil_printf("\r\n--- Part 2: Performance Benchmark (1 MiB Transfer) ---\r\n");

    XTime tStart, tEnd;
    u64 cycles_cpu, cycles_hw;
    u32 ms_cpu, ms_hw;
    u32 mbps_cpu, mbps_hw;

    XTime_GetTime(&tStart);
    golden_model(tx_buf, golden_buf, BENCH_BUF_LEN, OP_ADD_SAT, 25, 0, 0);
    XTime_GetTime(&tEnd);
    cycles_cpu = tEnd - tStart;
    ms_cpu = (u32)((cycles_cpu * 1000) / COUNTS_PER_SECOND);
    mbps_cpu = (ms_cpu > 0) ? (1000 / ms_cpu) : 0;
    xil_printf("ARM Cortex-A9 CPU (ADD_SAT 1 MiB):     %lu ms  (~%lu MB/s)\r\n",
               ms_cpu, mbps_cpu);

    Xil_Out32(STREAMOPS_MODE, OP_ADD_SAT);
    Xil_Out32(STREAMOPS_IMM8, 25);
    Xil_Out32(STREAMOPS_CTRL, 0x00000003);

    XTime_GetTime(&tStart);
    status = run_hw_op(BENCH_BUF_LEN);
    XTime_GetTime(&tEnd);

    if (status == XST_SUCCESS) {
        cycles_hw = tEnd - tStart;
        ms_hw = (u32)((cycles_hw * 1000) / COUNTS_PER_SECOND);
        mbps_hw = (ms_hw > 0) ? (1000 / ms_hw) : 0;
        xil_printf("FPGA Accelerator + DMA (ADD_SAT 1 MiB): %lu ms  (~%lu MB/s)\r\n",
                   ms_hw, mbps_hw);
        if (ms_hw > 0 && ms_cpu > 0) {
            xil_printf("Hardware Acceleration Speedup:           %lu.%lux faster\r\n",
                       ms_cpu / ms_hw, ((ms_cpu * 10) / ms_hw) % 10);
        }
    }

    xil_printf("\r\n============================================================\r\n");
    if (total_failures == 0) {
        xil_printf(">>> ALL SIMD OPERATIONS PASSED HARDWARE VALIDATION! <<<\r\n");
    } else {
        xil_printf(">>> HARDWARE TEST COMPLETED WITH %d FAILURES <<<\r\n", total_failures);
    }
    xil_printf("============================================================\r\n");

    return total_failures;
}
