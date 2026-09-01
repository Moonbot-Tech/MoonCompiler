# F4: x86-64 exception-aware register variables

Fast gate for the independent `-OoSEHREGVAR` mechanism. It proves identical
runtime semantics with the mechanism disabled/enabled, the handler/finally
memory-home boundaries, and the conservative fallback for user nested
routines.  Values computed from an opaque runtime parameter before a hardware
trap remain live after its returning handler; the matrix deliberately uses six
independent values so constant folding cannot replace the cross-handler state
with one literal digest.  The assignment coverage also includes a value whose first definition is
inside a guarded block and whose only read is after a returning handler, so a
pre-try initializer cannot accidentally mask the cross-handler requirement.
An independent method-result case returns `True` through an outlined `finally`
whose cleanup may clobber the ABI return register; it pins the frame home needed
by `Exit(value)` and the same shape used by queue-style `TryTake(out Value)`.
It also retains the distinct topology where a user nested routine owns the
guarded region and its compiler-generated handler reaches record fields in the
grandparent frame.  In that case the hidden static link deliberately has a
memory home and nested-variable lowering must materialize it in a temporary
address register rather than assuming it was allocated to a register.
The generated-cleanup coverage uses a class enumerator and proves destruction
on complete, break, and exceptional exits.  The assembly checks require both
an unrelated byte-scan loop and the compiler-generated `for-in` cleanup buyer
to stop round-tripping unrelated induction/reduction state through the stack
frame.  The authoritative check is the compiler's exact variable-location
metadata for `Value` and `Sum`: both must move from stack to registers.  Total
stack-reference count is only a non-regression ceiling because Linux LSDA keeps
the enumerator pointer and cleanup state in spill slots; those references may
replace the removed Value/Sum traffic one-for-one without losing the intended
optimization.

The gate runs natively on Win64 and Linux x86-64.  Linux linking under `-n`
locates `libgcc_s` through the host GCC driver.  Additional compiler search or
configuration options may be supplied by repeating `--compiler-option`.
