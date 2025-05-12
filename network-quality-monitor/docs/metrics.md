# Network Metrics Explained

This document explains the network quality metrics used in the Network Quality Monitor tool and how they are calculated and interpreted.

## Overview of Metrics

Network Quality Monitor tracks several important metrics:

1. **RTT (Round Trip Time)**: The time it takes for a packet to travel from source to destination and back
2. **Jitter**: Variation in packet delay
3. **TTL (Time To Live)**: Number of network hops before a packet is discarded
4. **Packet Loss**: Percentage of packets that don't reach their destination
5. **R-factor**: Voice quality metric based on ITU-T G.107 E-model
6. **MOS (Mean Opinion Score)**: Perceived voice quality metric derived from R-factor

## RTT (Round Trip Time)

RTT is the most basic network latency measurement.

### Calculation
- Measured directly by timing how long it takes to receive a response to each ICMP echo (ping) packet
- Displayed as MIN/AVG/MAX in milliseconds

### Interpretation
| Value | Color | Meaning |
|-------|-------|---------|
| < 80ms | Green | Good performance |
| 80-150ms | Yellow | Average performance, may impact some real-time applications |
| > 150ms | Red | Poor performance, likely to impact real-time applications |

## Jitter

Jitter refers to the variation in delay between packets. Low jitter is crucial for real-time applications like voice and video.

### Calculation
Network Quality Monitor uses the RFC 3550 EWMA (Exponential Weighted Moving Average) method with a 1/16 gain factor:

```
J(i) = J(i-1) + (|D(i-1,i)| - J(i-1))/16
```

Where:
- J(i) is the current jitter estimate
- J(i-1) is the previous jitter estimate
- |D(i-1,i)| is the absolute difference between successive RTT values

### Interpretation
| Value | Color | Meaning |
|-------|-------|---------|
| < 10ms | Green | Good - suitable for all applications |
| 10-30ms | Yellow | Warning - may impact sensitive applications |
| > 30ms | Red | Poor - likely to cause issues with real-time applications |

## TTL (Time To Live)

TTL indicates the number of network hops before a packet would be discarded. Changes in TTL can indicate routing changes.

### Calculation
- Extracted directly from the ICMP response packets
- Different operating systems set different initial TTL values (typically 64, 128, or 255)

### Interpretation
| Value | Color | Meaning |
|-------|-------|---------|
| ≥ 64 | Green | Normal TTL value |
| 32-63 | Yellow | Warning - unusual TTL, possible routing issues |
| < 32 | Red | Potential routing issue or very long path |

## Packet Loss

Packet loss represents the percentage of packets that don't receive a response.

### Calculation
- Calculated over each reporting interval
- Formula: `(lost_packets / total_packets) * 100`

### Interpretation
| Value | Color | Meaning |
|-------|-------|---------|
| 0% | Green | Perfect - no packet loss |
| > 0% but < threshold | Yellow | Some packet loss, but below alert threshold |
| ≥ threshold | Red | Excessive packet loss, alert triggered |

## R-factor

R-factor is based on the ITU-T G.107 E-model, a computational model for voice quality. It's on a scale of 0-100.

### Calculation
The R-factor is calculated as: `R = R0 - Is - Id - Ie-eff + A`

Where:
- **R0**: Basic signal-to-noise ratio (default: 93.2)
- **Is**: Simultaneous impairment factor (default: 1.4)
- **Id**: Delay impairment factor, calculated from one-way delay
- **Ie-eff**: Effective equipment impairment factor, accounting for codec quality, packet loss, and jitter
- **A**: Advantage factor (0 for wired connections, higher for mobile)

### Interpretation
| R-factor | Perceived Quality | Color |
|----------|-------------------|-------|
| ≥ 81 | Excellent/PSTN-like | Green |
| 71-80 | Good - most users satisfied | Green |
| 61-70 | Fair - some complaints | Yellow |
| 51-60 | Poor - many users dissatisfied | Yellow |
| < 50 | Bad - nearly all users dissatisfied | Red |

## MOS (Mean Opinion Score)

MOS is a measure of perceived voice quality, derived from the R-factor. It's on a scale of 1.0-5.0.

### Calculation
MOS is calculated from the R-factor using a formula from ITU-T G.107:
```
MOS = 1 + 0.035*R + 7*10^(-6)*R*(R-60)*(100-R)
```

### Interpretation
| MOS | Perceived Quality | Color |
|-----|-------------------|-------|
| > 4.0 | Excellent/Good | Green |
| 3.6-4.0 | Fair | Yellow |
| 3.1-3.5 | Poor | Yellow |
| < 3.0 | Bad | Red |

## Alert Types

Network Quality Monitor generates several types of alerts based on these metrics:

1. **[DOWN]**: Triggered when consecutive packet losses exceed the configured threshold
2. **[LOSS ALERT]**: Triggered when packet loss percentage exceeds the configured threshold
3. **[UP]**: Displayed when a previously down connection recovers

## Practical Use Cases

### VoIP Quality Assessment
- **Good quality**: R-factor > 80, MOS > 4.0, Jitter < 10ms, RTT < 80ms, Loss = 0%
- **Acceptable quality**: R-factor > 70, MOS > 3.6, Jitter < 20ms, RTT < 100ms, Loss < 1%
- **Poor quality**: R-factor < 70, MOS < 3.6, Jitter > 20ms, RTT > 100ms, Loss > 1%

### Online Gaming
- **Good experience**: RTT < 50ms, Jitter < 5ms, Loss = 0%
- **Acceptable experience**: RTT < 100ms, Jitter < 10ms, Loss < 0.5%
- **Poor experience**: RTT > 100ms, Jitter > 10ms, Loss > 0.5%

### General Web Browsing
- **Good experience**: RTT < 100ms, Loss < 1%
- **Acceptable experience**: RTT < 200ms, Loss < 5%
- **Poor experience**: RTT > 200ms, Loss > 5%

## References

- ITU-T G.107 E-model: [ITU-T G.107 Recommendation](https://www.itu.int/rec/T-REC-G.107)
- RFC 3550 (RTP protocol and jitter calculation): [RFC 3550](https://tools.ietf.org/html/rfc3550)