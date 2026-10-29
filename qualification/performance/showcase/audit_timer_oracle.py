"""Independent timer oracle: merge arithmetic progressions without simulating a heap."""

import json


def timer_checksum(operations):
    def count_through(deadline):
        return sum(
            (deadline - token * 19) // (100000 + token) + 1
            for token in range(8192)
            if deadline >= token * 19
        )

    low, high = 0, operations * 108191
    while low < high:
        mid = (low + high) // 2
        if count_through(mid) >= operations:
            high = mid
        else:
            low = mid + 1
    cutoff = low
    # For the specified workloads the last deadline is unique. If the case is
    # changed to stop within a tied group, an exact checksum needs a tie policy.
    assert count_through(cutoff) == operations, "cutoff splits a tied group"
    checksum = 0
    for token in range(8192):
        count = max(0, (cutoff - token * 19) // (100000 + token) + 1)
        checksum += count * token * 20 + (100000 + token) * count * (count - 1) // 2
    return checksum


if __name__ == "__main__":
    print(
        json.dumps(
            {str(passes): timer_checksum(passes * 100000) for passes in (1, 32)},
            indent=2,
        )
    )
