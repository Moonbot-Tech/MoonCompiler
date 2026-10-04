/* Moon.Diagnostics' small C ABI over Zydis (MIT). No EurekaLog code is used. */
#include <Zydis/Zydis.h>
#include <Zycore/LibC.h>

typedef struct MoonMemoryOperand {
    ZyanU64 address, base;
    ZyanU32 flags, bits; /* 1 address valid, 2 base valid, 4 read, 8 write */
} MoonMemoryOperand;

/* Register order is the diagnostic snapshot order, not an OS or Zydis ABI. */
static const ZydisRegister moon_regs[16] = {
    ZYDIS_REGISTER_R8, ZYDIS_REGISTER_R9, ZYDIS_REGISTER_R10, ZYDIS_REGISTER_R11,
    ZYDIS_REGISTER_R12, ZYDIS_REGISTER_R13, ZYDIS_REGISTER_R14, ZYDIS_REGISTER_R15,
    ZYDIS_REGISTER_RDI, ZYDIS_REGISTER_RSI, ZYDIS_REGISTER_RBP, ZYDIS_REGISTER_RBX,
    ZYDIS_REGISTER_RDX, ZYDIS_REGISTER_RAX, ZYDIS_REGISTER_RCX, ZYDIS_REGISTER_RSP
};

/* Only fixed-size caller buffers. Formatting is optional and never requested
   by early capture. Zero means invalid/truncated instruction, not a guess. */
unsigned moon_decode(const void *bytes, ZyanUSize size, ZyanU64 ip,
    const ZyanU64 *regs, MoonMemoryOperand *memory, char *text, ZyanUSize text_size)
{
    ZydisDecoder decoder;
    ZydisDecodedInstruction ins;
    ZydisDecodedOperand ops[ZYDIS_MAX_OPERAND_COUNT];
    if (!ZYAN_SUCCESS(ZydisDecoderInit(&decoder, ZYDIS_MACHINE_MODE_LONG_64, ZYDIS_STACK_WIDTH_64)) ||
        !ZYAN_SUCCESS(ZydisDecoderDecodeFull(&decoder, bytes, size, &ins, ops)))
        return 0;
    if (text) {
        ZydisFormatter formatter;
        if (!ZYAN_SUCCESS(ZydisFormatterInit(&formatter, ZYDIS_FORMATTER_STYLE_INTEL)) ||
            !ZYAN_SUCCESS(ZydisFormatterFormatInstruction(&formatter, &ins, ops,
                ins.operand_count_visible, text, text_size, ip, ZYAN_NULL)))
            return 0;
    }
    if (regs && memory) {
        ZydisRegisterContext ctx;
        unsigned i, n = 0;
        ZYAN_MEMSET(&ctx, 0, sizeof(ctx));
        ZYAN_MEMSET(memory, 0, 2 * sizeof(*memory));
        for (i = 0; i < 16; ++i) {
            ctx.values[moon_regs[i]] = regs[i];
            ctx.values[ZYDIS_REGISTER_EAX + moon_regs[i] - ZYDIS_REGISTER_RAX] = (ZyanU32)regs[i];
        }
        for (i = 0; i < ins.operand_count && n < 2; ++i) {
            const ZydisDecodedOperand *op = &ops[i];
            /* FS/GS bases and vector indices are not present in this snapshot.
               AGEN/MIB operands do not describe a normal memory access. */
            if (op->type != ZYDIS_OPERAND_TYPE_MEMORY || op->mem.type != ZYDIS_MEMOP_TYPE_MEM ||
                op->mem.segment == ZYDIS_REGISTER_FS || op->mem.segment == ZYDIS_REGISTER_GS)
                continue;
            if (!ZYAN_SUCCESS(ZydisCalcAbsoluteAddressEx(&ins, op, ip, &ctx, &memory[n].address)))
                continue;
            memory[n].flags = 1;
            memory[n].bits = op->size;
            if (op->actions & ZYDIS_OPERAND_ACTION_MASK_READ) memory[n].flags |= 4;
            if (op->actions & ZYDIS_OPERAND_ACTION_MASK_WRITE) memory[n].flags |= 8;
            if (op->mem.base != ZYDIS_REGISTER_NONE && op->mem.base != ZYDIS_REGISTER_RIP &&
                op->mem.base != ZYDIS_REGISTER_EIP) {
                memory[n].base = ctx.values[op->mem.base];
                memory[n].flags |= 2;
            }
            ++n;
        }
    }
    return ins.length;
}
