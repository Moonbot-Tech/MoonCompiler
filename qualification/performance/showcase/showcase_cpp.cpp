#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <iomanip>
#include <iostream>
#include <limits>
#include <memory>
#include <semaphore>
#include <stdexcept>
#include <string>
#include <string_view>
#include <thread>
#include <unordered_map>
#include <vector>
#include <time.h>

using std::uint32_t;
using std::uint64_t;

uint64_t clock_ns(clockid_t clock) {
    timespec time{};
    if (clock_gettime(clock, &time) != 0) {
        throw std::runtime_error("clock_gettime failed");
    }
    return uint64_t(time.tv_sec) * 1'000'000'000 + uint64_t(time.tv_nsec);
}

struct Measurement {
    uint64_t wall_ns;
    uint64_t cpu_ns;
};

class Stopwatch {
    uint64_t cpu_start_ = clock_ns(CLOCK_PROCESS_CPUTIME_ID);
    uint64_t wall_start_ = clock_ns(CLOCK_MONOTONIC);

public:
    Measurement elapsed() const {
        const auto wall = clock_ns(CLOCK_MONOTONIC) - wall_start_;
        const auto cpu = clock_ns(CLOCK_PROCESS_CPUTIME_ID) - cpu_start_;
        return {wall, cpu};
    }
};

void begin_report(std::string_view mode, Measurement time, uint64_t operations) {
    std::cout << "{\"case\":\"" << mode << "\",\"wall_ns\":" << time.wall_ns
              << ",\"cpu_ns\":" << time.cpu_ns << ",\"operations\":" << operations;
}

struct Sample {
    double price;
    double quantity;
    std::int64_t time;
    std::int32_t side;
};

std::vector<Sample> make_samples() {
    std::vector<Sample> samples(262144);
    for (size_t i = 0; i < samples.size(); ++i) {
        samples[i] = {(i % 10000 + 1) / 64.0, (i % 100 + 1) / 128.0,
                      std::int64_t(i), std::int32_t(i & 1)};
    }
    return samples;
}

// Runtime-sized input, just like the Pascal const dynamic-array parameter.
// Ordinary compiler inlining is allowed; there are no benchmark-only attributes.
double analyze_windows(const std::vector<Sample>& samples, int passes) {
    double result = 0;
    for (uint64_t window = 0; window < uint64_t(passes) * 4096; ++window) {
        const size_t end = 512 + (window * 7919) % (samples.size() - 512);
        const size_t length = 64 + window % 449;
        double buy_turnover = 0;
        double sell_turnover = 0;
        double maximum_price = 0;
        double quantity = 0;
        for (size_t i = end - length; i < end; ++i) {
            const auto& sample = samples[i];
            const double price = sample.price;
            const double trade_quantity = sample.quantity;
            const double turnover = price * trade_quantity;
            if (sample.side == 0) {
                buy_turnover += turnover;
            } else {
                sell_turnover += turnover;
            }
            if (price > maximum_price) {
                maximum_price = price;
            }
            quantity += trade_quantity;
        }
        result += buy_turnover + sell_turnover + maximum_price + (buy_turnover + sell_turnover) / quantity;
    }
    return result;
}

void run_analytics(int passes) {
    const auto samples = make_samples();
    const Stopwatch timer;
    const double result = analyze_windows(samples, passes);
    const auto elapsed = timer.elapsed();
    begin_report("analytics", elapsed, uint64_t(passes) * 4096);
    std::cout << ",\"result\":" << std::setprecision(17) << result << "}\n";
}

struct Timer {
    uint64_t deadline;
    uint64_t token;
};

// Rescheduling can only move the earliest event down the min-heap.
// Equal deadlines keep the same left-child preference as the Pascal version.
void replace_earliest(std::vector<Timer>& heap, Timer event) {
    size_t root = 0;
    while (root < heap.size() / 2) {
        size_t child = root * 2 + 1;
        if (child + 1 < heap.size() && heap[child + 1].deadline < heap[child].deadline) {
            ++child;
        }
        if (event.deadline <= heap[child].deadline) {
            break;
        }
        heap[root] = heap[child];
        root = child;
    }
    heap[root] = event;
}

void run_timers(int passes) {
    std::vector<Timer> heap(8192);
    for (size_t i = 0; i < heap.size(); ++i) {
        heap[i] = {i * 19, i};
    }
    uint64_t checksum = 0;
    const uint64_t operations = uint64_t(passes) * 100000;
    const Stopwatch timer;
    for (uint64_t i = 0; i < operations; ++i) {
        auto event = heap.front();
        checksum += event.deadline + event.token;
        event.deadline += 100000 + (event.token & 0x3fff);
        replace_earliest(heap, event);
    }
    const auto elapsed = timer.elapsed();
    begin_report("timers", elapsed, operations);
    std::cout << ",\"checksum\":" << checksum << "}\n";
}

constexpr size_t initial_entries = 100000;
constexpr size_t key_space = 111111;
using IntegerMap = std::unordered_map<uint64_t, uint64_t>;

std::vector<uint32_t> make_queries() {
    std::vector<uint32_t> queries(1000000);
    uint32_t state = 123456789;
    for (auto& query : queries) {
        state = state * 1664525u + 1013904223u;
        query = state % key_space;
    }
    return queries;
}

void run_string_lookup(int passes) {
    std::unordered_map<std::string, uint64_t> markets;
    markets.reserve(initial_entries);
    std::vector<std::string> keys(initial_entries);
    for (size_t i = 0; i < keys.size(); ++i) {
        char name[32];
        std::snprintf(name, sizeof(name), "MARKET_%08X", unsigned(i));
        keys[i] = name;
        markets.emplace(keys[i], i * 17 + 3);
    }
    const auto queries = make_queries();
    std::vector<std::string> query_keys;
    query_keys.reserve(queries.size());
    for (auto query : queries) {
        query_keys.push_back(query < keys.size() ? keys[query] : "MISSING");
    }

    uint64_t checksum = 0;
    const Stopwatch timer;
    for (int pass = 0; pass < passes; ++pass) {
        for (const auto& key : query_keys) {
            const auto found = markets.find(key);
            if (found != markets.end()) {
                checksum += found->second;
            }
        }
    }
    const auto elapsed = timer.elapsed();
    begin_report("dict-string", elapsed, queries.size() * uint64_t(passes));
    std::cout << ",\"checksum\":" << checksum << ",\"final_checksum\":0,\"final_count\":0}\n";
}

struct MapSummary {
    uint64_t checksum = 0;
    uint64_t count = 0;
};

MapSummary validate_integer_map(const IntegerMap& values, const std::vector<uint64_t>& expected) {
    MapSummary summary;
    for (size_t key = 0; key < expected.size(); ++key) {
        const auto found = values.find(key);
        if (expected[key] == std::numeric_limits<uint64_t>::max()) {
            if (found != values.end()) {
                throw std::runtime_error("unexpected integer key");
            }
        } else {
            if (found == values.end() || found->second != expected[key]) {
                throw std::runtime_error("integer map value mismatch");
            }
            summary.checksum += found->second;
            ++summary.count;
        }
    }
    if (values.size() != summary.count) {
        throw std::runtime_error("integer map size mismatch");
    }
    return summary;
}

void run_integer_updates(int passes, bool read_after_update) {
    IntegerMap values;
    values.reserve(initial_entries);
    for (size_t key = 0; key < initial_entries; ++key) {
        values.emplace(key, key * 17 + 3);
    }
    const auto queries = make_queries();
    std::vector<uint64_t> expected(key_space, std::numeric_limits<uint64_t>::max());
    for (size_t key = 0; key < initial_entries; ++key) {
        expected[key] = key * 17 + 3;
    }
    for (size_t i = 0; i < queries.size(); ++i) {
        expected[queries[i]] = i + uint64_t(passes);
    }

    uint64_t checksum = 0;
    const Stopwatch timer;
    if (read_after_update) {
        for (int pass = 1; pass <= passes; ++pass) {
            for (size_t i = 0; i < queries.size(); ++i) {
                values.insert_or_assign(queries[i], uint64_t(i) + pass);
                checksum += values.at(queries[i]);
            }
        }
    } else {
        for (int pass = 1; pass <= passes; ++pass) {
            for (size_t i = 0; i < queries.size(); ++i) {
                values.insert_or_assign(queries[i], uint64_t(i) + pass);
            }
        }
    }
    const auto elapsed = timer.elapsed();
    const auto final_state = validate_integer_map(values, expected);
    begin_report(read_after_update ? "dict-int-update-read" : "dict-int-update", elapsed,
                 queries.size() * uint64_t(passes));
    std::cout << ",\"checksum\":" << checksum << ",\"final_checksum\":" << final_state.checksum
              << ",\"final_count\":" << final_state.count << "}\n";
}

void run_ring(int count, int rounds) {
    uint64_t counter = 0;
    std::atomic<int> ready = 0;
    std::atomic<bool> started = false;
    std::vector<std::unique_ptr<std::binary_semaphore>> events;
    events.reserve(count);
    for (int i = 0; i < count; ++i) {
        events.push_back(std::make_unique<std::binary_semaphore>(0));
    }
    std::binary_semaphore done(0);
    std::vector<uint64_t> timeouts(count);
    std::vector<uint64_t> received(count);
    const uint64_t transfers = uint64_t(count) * rounds;

    std::vector<std::thread> workers;
    workers.reserve(count);
    for (int id = 0; id < count; ++id) {
        workers.emplace_back([&, id] {
            ++ready;
            for (int round = 0; round < rounds;) {
                if (!events[id]->try_acquire_for(std::chrono::milliseconds(16))) {
                    if (started.load()) {
                        ++timeouts[id];
                    }
                    continue;
                }
                // The baton orders all accesses to this non-atomic counter.
                if (counter != uint64_t(round) * count + id) {
                    std::terminate();
                }
                ++counter;
                ++received[id];
                ++round;
                if (counter == transfers) {
                    done.release();
                } else {
                    events[(id + 1) % count]->release();
                }
            }
        });
    }
    while (ready.load() != count) {
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    const Stopwatch timer;
    started = true;
    events.front()->release();
    done.acquire();
    const auto elapsed = timer.elapsed();
    for (auto& worker : workers) {
        worker.join();
    }
    uint64_t total_timeouts = 0;
    for (int id = 0; id < count; ++id) {
        if (received[id] != uint64_t(rounds)) {
            throw std::runtime_error("ring receive count mismatch");
        }
        total_timeouts += timeouts[id];
    }
    begin_report("ring", elapsed, counter);
    std::cout << ",\"threads\":" << count << ",\"timeouts\":" << total_timeouts << "}\n";
}

int positive_argument(const char* argument) {
    size_t consumed = 0;
    const std::string text(argument);
    const int value = std::stoi(text, &consumed);
    if (value <= 0 || value == std::numeric_limits<int>::max() || consumed != text.size()) {
        throw std::invalid_argument("expected a positive integer below INT_MAX");
    }
    return value;
}

int main(int argc, char** argv) {
    if (argc < 3 || argc > 4) {
        throw std::invalid_argument("usage: showcase_cpp CASE DATA_DIR_OR_THREADS [PASSES]");
    }
    const std::string_view mode = argv[1];
    const int passes = argc > 3 ? positive_argument(argv[3]) : 1;
    if (mode == "analytics") {
        run_analytics(passes);
    } else if (mode == "timers") {
        run_timers(passes);
    } else if (mode == "dict-string") {
        run_string_lookup(passes);
    } else if (mode == "dict-int-update" || mode == "dict-int-update-read") {
        run_integer_updates(passes, mode == "dict-int-update-read");
    } else if (mode == "ring") {
        run_ring(positive_argument(argv[2]), passes);
    } else {
        throw std::invalid_argument("unknown case");
    }
}
