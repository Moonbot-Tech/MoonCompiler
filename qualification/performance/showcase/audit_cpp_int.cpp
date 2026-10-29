// Control: consume the iterator returned by insert_or_assign, without a second lookup.
#include <cstdint>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <string>
#include <unordered_map>
#include <vector>
#include <time.h>

using std::uint32_t;
using std::uint64_t;
using IntegerMap = std::unordered_map<uint64_t, uint64_t>;
constexpr size_t initial_entries = 100000;
constexpr size_t key_space = 111111;

uint64_t clock_ns(clockid_t clock) {
    timespec time{};
    if (clock_gettime(clock, &time) != 0) {
        throw std::runtime_error("clock_gettime failed");
    }
    return uint64_t(time.tv_sec) * 1'000'000'000 + uint64_t(time.tv_nsec);
}

std::vector<uint32_t> make_queries() {
    std::vector<uint32_t> queries(1000000);
    uint32_t state = 123456789;
    for (auto& query : queries) {
        state = state * 1664525u + 1013904223u;
        query = state % key_space;
    }
    return queries;
}

size_t validate_final_state(const IntegerMap& values, const std::vector<uint32_t>& queries, int passes) {
    // Independent representation, outside timing: no hash table in the oracle.
    constexpr uint64_t absent = std::numeric_limits<uint64_t>::max();
    std::vector<uint64_t> expected(key_space, absent);
    for (size_t key = 0; key < initial_entries; ++key) {
        expected[key] = key * 17 + 3;
    }
    for (size_t i = 0; i < queries.size(); ++i) {
        expected[queries[i]] = i + uint64_t(passes);
    }
    size_t count = 0;
    for (size_t key = 0; key < expected.size(); ++key) {
        const auto found = values.find(key);
        if (expected[key] == absent) {
            if (found != values.end()) {
                throw std::runtime_error("unexpected integer key");
            }
        } else {
            ++count;
            if (found == values.end() || found->second != expected[key]) {
                throw std::runtime_error("integer map value mismatch");
            }
        }
    }
    if (values.size() != count) {
        throw std::runtime_error("integer map size mismatch");
    }
    return count;
}

void run_iterator_updates(int passes) {
    IntegerMap values;
    values.reserve(initial_entries);
    for (size_t key = 0; key < initial_entries; ++key) {
        values.emplace(key, key * 17 + 3);
    }
    const auto queries = make_queries();
    uint64_t checksum = 0;
    const auto cpu_start = clock_ns(CLOCK_PROCESS_CPUTIME_ID);
    const auto wall_start = clock_ns(CLOCK_MONOTONIC);
    for (int pass = 1; pass <= passes; ++pass) {
        for (size_t i = 0; i < queries.size(); ++i) {
            const auto [entry, inserted] = values.insert_or_assign(queries[i], uint64_t(i) + pass);
            checksum += entry->second;
        }
    }
    const auto wall = clock_ns(CLOCK_MONOTONIC) - wall_start;
    const auto cpu = clock_ns(CLOCK_PROCESS_CPUTIME_ID) - cpu_start;
    const auto count = validate_final_state(values, queries, passes);
    const auto query_count = uint64_t(queries.size());
    const auto pass_count = uint64_t(passes);
    const auto expected_checksum = pass_count * query_count * (query_count - 1) / 2
                                 + query_count * pass_count * (pass_count + 1) / 2;
    if (checksum != expected_checksum) {
        throw std::runtime_error("update checksum mismatch");
    }
    std::cout << "{\"case\":\"dict-int-update-iterator\",\"wall_ns\":" << wall
              << ",\"cpu_ns\":" << cpu << ",\"operations\":" << query_count * pass_count
              << ",\"checksum\":" << checksum << ",\"final_count\":" << count << "}\n";
}

int main(int argc, char** argv) {
    const std::string text = argc > 3 ? argv[3] : "1";
    size_t consumed = 0;
    const int passes = std::stoi(text, &consumed);
    if (passes <= 0 || passes == std::numeric_limits<int>::max() || consumed != text.size()) {
        throw std::invalid_argument("expected a positive pass count below INT_MAX");
    }
    run_iterator_updates(passes);
}
