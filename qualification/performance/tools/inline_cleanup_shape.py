"""Check that a Win64 implicit cleanup runs directly on normal return and keeps its SEH finalizer."""

import re

HEAD = re.compile(r"^[0-9a-f]+ <(.+)>:$")
CALL = re.compile(r"^\s*[0-9a-f]+:\s*call\b.*")
RELOC = re.compile(r"[0-9a-f]+: R_\S+\s+(\S+)")
TARGET = re.compile(r"<([^>]+)>")


def calls_by_routine(listing):
    found = {}
    name = None
    for line in listing.splitlines():
        head = HEAD.match(line)
        if head:
            name = head[1].upper()
            found[name] = []
            continue
        if name is None:
            continue
        if CALL.match(line):
            reloc = RELOC.search(line)
            target = TARGET.search(line)
            found[name].append((reloc or target)[1].upper() if reloc or target else "<UNRESOLVED>")
    return found


def problems(listing, shape, cleanup, count):
    """One parent and one cold _fin$, each with the same direct cleanup calls."""
    routines = calls_by_routine(listing)
    parent_token = f"_$$_{shape}$"
    finalizer_tokens = (f"$_${shape}$", f"_$_{shape}$")
    parents = [name for name in routines if parent_token in name and "_FIN$" not in name]
    finalizers = [name for name in routines if any(token in name for token in finalizer_tokens)
                  and "_FIN$" in name]
    if len(parents) != 1 or len(finalizers) != 1:
        return [f"{shape}: expected one parent and one cold SEH finalizer, got {len(parents)}/{len(finalizers)}"]
    parent_calls, finalizer_calls = routines[parents[0]], routines[finalizers[0]]
    if any("_FIN$" in call for call in parent_calls):
        return [f"{shape}: normal path still calls an outlined finalizer"]
    helper = cleanup.upper()
    if parent_calls.count(helper) != count or finalizer_calls.count(helper) != count:
        return [f"{shape}: direct/cold {cleanup} calls are {parent_calls.count(helper)}/"
                f"{finalizer_calls.count(helper)}, expected {count}/{count}"]
    return []
