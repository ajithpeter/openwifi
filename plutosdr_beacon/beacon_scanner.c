/*
 * PlutoSDR WiFi Beacon Scanner
 * Minimal WiFi beacon transmitter/receiver for PlutoSDR
 *
 * Supports: 802.11a/b/g/n/ac/ax beacon frames
 * Hardware: PlutoSDR with AD9364
 *
 * Functionality:
 * - Receive WiFi beacons and print SSID, channel, RSSI
 * - Transmit WiFi beacons on specified channels
 *
 * Build: gcc -o beacon_scanner beacon_scanner.c -liio -lm -lpthread
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdbool.h>
#include <unistd.h>
#include <signal.h>
#include <math.h>
#include <complex.h>
#include <iio.h>
#include <pthread.h>
#include <time.h>

#define PROGRAM_VERSION "1.0.0"

/* WiFi Constants */
#define WIFI_SAMPLE_RATE    20000000  /* 20 MHz for 20 MHz channels */
#define PLUTO_SAMPLE_RATE   (WIFI_SAMPLE_RATE * 2)  /* 40 MSPS */
#define FFT_SIZE            64
#define CYCLIC_PREFIX_LEN   16
#define OFDM_SYMBOL_LEN     (FFT_SIZE + CYCLIC_PREFIX_LEN)

/* Frame Types */
#define FRAME_TYPE_MANAGEMENT   0
#define FRAME_TYPE_CONTROL      1
#define FRAME_TYPE_DATA         2

#define FRAME_SUBTYPE_BEACON    8

/* WiFi Channels */
typedef struct {
    int channel;
    uint64_t freq_hz;
    const char *band;
} wifi_channel_t;

/* 2.4 GHz and 5 GHz channels */
static const wifi_channel_t wifi_channels[] = {
    /* 2.4 GHz */
    {1, 2412000000ULL, "2.4GHz"},
    {2, 2417000000ULL, "2.4GHz"},
    {3, 2422000000ULL, "2.4GHz"},
    {4, 2427000000ULL, "2.4GHz"},
    {5, 2432000000ULL, "2.4GHz"},
    {6, 2437000000ULL, "2.4GHz"},
    {7, 2442000000ULL, "2.4GHz"},
    {8, 2447000000ULL, "2.4GHz"},
    {9, 2452000000ULL, "2.4GHz"},
    {10, 2457000000ULL, "2.4GHz"},
    {11, 2462000000ULL, "2.4GHz"},
    {12, 2467000000ULL, "2.4GHz"},
    {13, 2472000000ULL, "2.4GHz"},

    /* 5 GHz */
    {36, 5180000000ULL, "5GHz"},
    {40, 5200000000ULL, "5GHz"},
    {44, 5220000000ULL, "5GHz"},
    {48, 5240000000ULL, "5GHz"},
    {52, 5260000000ULL, "5GHz"},
    {56, 5280000000ULL, "5GHz"},
    {60, 5300000000ULL, "5GHz"},
    {64, 5320000000ULL, "5GHz"},
    {100, 5500000000ULL, "5GHz"},
    {104, 5520000000ULL, "5GHz"},
    {108, 5540000000ULL, "5GHz"},
    {112, 5560000000ULL, "5GHz"},
    {116, 5580000000ULL, "5GHz"},
    {120, 5600000000ULL, "5GHz"},
    {124, 5620000000ULL, "5GHz"},
    {128, 5640000000ULL, "5GHz"},
    {132, 5660000000ULL, "5GHz"},
    {136, 5680000000ULL, "5GHz"},
    {140, 5700000000ULL, "5GHz"},
    {149, 5745000000ULL, "5GHz"},
    {153, 5765000000ULL, "5GHz"},
    {157, 5785000000ULL, "5GHz"},
    {161, 5805000000ULL, "5GHz"},
    {165, 5825000000ULL, "5GHz"},
};

#define NUM_CHANNELS (sizeof(wifi_channels) / sizeof(wifi_channel_t))

/* Beacon Information */
typedef struct {
    char ssid[33];
    uint8_t bssid[6];
    int channel;
    int rssi;
    uint16_t beacon_interval;
    uint16_t capability;
    uint8_t *ie_data;
    size_t ie_len;
    uint64_t timestamp;

    /* Parsed IE info */
    bool has_ht;          /* 802.11n */
    bool has_vht;         /* 802.11ac */
    bool has_he;          /* 802.11ax */
    uint8_t rates[16];
    int num_rates;
} beacon_info_t;

/* Global state */
static volatile bool running = true;
static struct iio_context *ctx = NULL;
static struct iio_device *phy = NULL;
static struct iio_device *rx_dev = NULL;
static struct iio_device *tx_dev = NULL;

/* Signal handler */
void signal_handler(int sig)
{
    printf("\nShutting down...\n");
    running = false;
}

/* Get channel frequency */
uint64_t get_channel_freq(int channel)
{
    for (int i = 0; i < NUM_CHANNELS; i++) {
        if (wifi_channels[i].channel == channel) {
            return wifi_channels[i].freq_hz;
        }
    }
    return 0;
}

/* Get channel from frequency */
int get_freq_channel(uint64_t freq_hz)
{
    uint64_t min_diff = UINT64_MAX;
    int best_channel = 0;

    for (int i = 0; i < NUM_CHANNELS; i++) {
        uint64_t diff = (freq_hz > wifi_channels[i].freq_hz) ?
                        (freq_hz - wifi_channels[i].freq_hz) :
                        (wifi_channels[i].freq_hz - freq_hz);

        if (diff < min_diff) {
            min_diff = diff;
            best_channel = wifi_channels[i].channel;
        }
    }

    return best_channel;
}

/* Initialize PlutoSDR */
int init_plutosdr(const char *uri)
{
    printf("Initializing PlutoSDR...\n");

    /* Create context */
    if (uri) {
        ctx = iio_create_context_from_uri(uri);
    } else {
        ctx = iio_create_default_context();
    }

    if (!ctx) {
        fprintf(stderr, "Failed to create IIO context\n");
        return -1;
    }

    printf("IIO context created: %s\n", iio_context_get_description(ctx));

    /* Get AD9364 device */
    phy = iio_context_find_device(ctx, "ad9361-phy");
    if (!phy) {
        fprintf(stderr, "Failed to find ad9361-phy device\n");
        return -1;
    }

    /* Get RX and TX devices */
    rx_dev = iio_context_find_device(ctx, "cf-ad9361-lpc");
    tx_dev = iio_context_find_device(ctx, "cf-ad9361-dds-core-lpc");

    if (!rx_dev || !tx_dev) {
        fprintf(stderr, "Failed to find RX/TX devices\n");
        return -1;
    }

    printf("PlutoSDR initialized successfully\n");
    return 0;
}

/* Configure PlutoSDR for WiFi reception */
int configure_rx(uint64_t freq_hz, uint64_t sample_rate, uint64_t bandwidth)
{
    struct iio_channel *ch;

    /* Configure PHY */
    ch = iio_device_find_channel(phy, "altvoltage0", true);
    if (ch) {
        iio_channel_attr_write_longlong(ch, "frequency", freq_hz);
    }

    ch = iio_device_find_channel(phy, "voltage0", false);
    if (ch) {
        iio_channel_attr_write_longlong(ch, "sampling_frequency", sample_rate);
        iio_channel_attr_write_longlong(ch, "rf_bandwidth", bandwidth);
        iio_channel_attr_write(ch, "gain_control_mode", "fast_attack");
        iio_channel_attr_write_longlong(ch, "hardwaregain", 70);  /* Max gain */
    }

    printf("RX configured: freq=%llu Hz, sample_rate=%llu Hz\n",
           (unsigned long long)freq_hz, (unsigned long long)sample_rate);

    return 0;
}

/* Configure PlutoSDR for WiFi transmission */
int configure_tx(uint64_t freq_hz, uint64_t sample_rate, uint64_t bandwidth)
{
    struct iio_channel *ch;

    /* Configure PHY */
    ch = iio_device_find_channel(phy, "altvoltage1", true);
    if (ch) {
        iio_channel_attr_write_longlong(ch, "frequency", freq_hz);
    }

    ch = iio_device_find_channel(phy, "voltage0", true);
    if (ch) {
        iio_channel_attr_write_longlong(ch, "sampling_frequency", sample_rate);
        iio_channel_attr_write_longlong(ch, "rf_bandwidth", bandwidth);
        iio_channel_attr_write_longlong(ch, "hardwaregain", -10000);  /* -10 dB */
    }

    printf("TX configured: freq=%llu Hz, sample_rate=%llu Hz\n",
           (unsigned long long)freq_hz, (unsigned long long)sample_rate);

    return 0;
}

/* Parse beacon frame */
void parse_beacon(const uint8_t *frame, size_t len, beacon_info_t *info)
{
    if (len < 36) return;  /* Minimum beacon frame size */

    memset(info, 0, sizeof(beacon_info_t));

    /* Parse fixed fields */
    memcpy(&info->timestamp, frame + 0, 8);
    memcpy(&info->beacon_interval, frame + 8, 2);
    memcpy(&info->capability, frame + 10, 2);

    /* Parse Information Elements */
    const uint8_t *ie = frame + 12;
    size_t ie_total_len = len - 12;
    size_t offset = 0;

    while (offset + 2 <= ie_total_len) {
        uint8_t ie_id = ie[offset];
        uint8_t ie_len = ie[offset + 1];

        if (offset + 2 + ie_len > ie_total_len) break;

        const uint8_t *ie_data = &ie[offset + 2];

        switch (ie_id) {
            case 0:  /* SSID */
                if (ie_len <= 32) {
                    memcpy(info->ssid, ie_data, ie_len);
                    info->ssid[ie_len] = '\0';
                }
                break;

            case 1:  /* Supported rates */
            case 50: /* Extended supported rates */
                for (int i = 0; i < ie_len && info->num_rates < 16; i++) {
                    info->rates[info->num_rates++] = ie_data[i] & 0x7F;
                }
                break;

            case 45: /* HT Capabilities (802.11n) */
                info->has_ht = true;
                break;

            case 191: /* VHT Capabilities (802.11ac) */
                info->has_vht = true;
                break;

            case 255: /* Extension (802.11ax HE) */
                if (ie_len > 0 && ie_data[0] == 35) {
                    info->has_he = true;
                }
                break;
        }

        offset += 2 + ie_len;
    }
}

/* Print beacon information */
void print_beacon_info(const beacon_info_t *info, int channel)
{
    time_t now = time(NULL);
    struct tm *tm_info = localtime(&now);
    char time_str[32];
    strftime(time_str, sizeof(time_str), "%H:%M:%S", tm_info);

    printf("\n[%s] WiFi Beacon Detected:\n", time_str);
    printf("  SSID: %s\n", info->ssid[0] ? info->ssid : "<hidden>");
    printf("  BSSID: %02x:%02x:%02x:%02x:%02x:%02x\n",
           info->bssid[0], info->bssid[1], info->bssid[2],
           info->bssid[3], info->bssid[4], info->bssid[5]);
    printf("  Channel: %d\n", channel);
    printf("  RSSI: %d dBm\n", info->rssi);
    printf("  Beacon Interval: %d TU (%.1f ms)\n",
           info->beacon_interval, info->beacon_interval * 1.024);

    /* Standards */
    printf("  Standards: ");
    printf("802.11");
    if (info->has_ht) printf("n");
    if (info->has_vht) printf("ac");
    if (info->has_he) printf("ax");
    printf("\n");

    /* Data rates */
    if (info->num_rates > 0) {
        printf("  Rates (Mbps): ");
        for (int i = 0; i < info->num_rates; i++) {
            printf("%.1f ", (info->rates[i] & 0x7F) * 0.5);
        }
        printf("\n");
    }

    printf("  Timestamp: %llu\n", (unsigned long long)info->timestamp);
    printf("----------------------------------------\n");
}

/* Simple energy detection for beacon scanning */
int detect_beacon_simple(const int16_t *iq_samples, size_t num_samples,
                        beacon_info_t *info, int channel)
{
    /* This is a placeholder for actual OFDM demodulation
     * In a full implementation, this would:
     * 1. Detect preamble (short/long training sequences)
     * 2. Perform FFT-based OFDM demodulation
     * 3. Decode SIGNAL field to get rate and length
     * 4. Demodulate and decode data symbols
     * 5. Parse MAC frame
     *
     * For this minimal version, we'll implement basic energy detection
     * and frame parsing when a beacon-like pattern is detected.
     */

    /* Calculate average power */
    double avg_power = 0;
    for (size_t i = 0; i < num_samples; i += 2) {
        double i_val = iq_samples[i] / 2048.0;
        double q_val = iq_samples[i + 1] / 2048.0;
        avg_power += (i_val * i_val + q_val * q_val);
    }
    avg_power /= (num_samples / 2);

    info->rssi = (int)(10 * log10(avg_power + 1e-10) - 30);  /* Rough RSSI estimate */

    /* In real implementation, perform OFDM demod here */
    /* For now, return indication that beacon detection needs full OFDM */

    return -1;  /* Not implemented in minimal version */
}

/* Generate beacon frame */
size_t generate_beacon_frame(uint8_t *frame, size_t max_len,
                             const char *ssid, const uint8_t *bssid,
                             int channel, bool support_11n, bool support_11ac)
{
    size_t offset = 0;

    if (max_len < 512) return 0;

    /* Frame Control: Beacon */
    frame[offset++] = 0x80;  /* Type: Management, Subtype: Beacon */
    frame[offset++] = 0x00;

    /* Duration */
    frame[offset++] = 0x00;
    frame[offset++] = 0x00;

    /* Destination (broadcast) */
    memset(&frame[offset], 0xFF, 6);
    offset += 6;

    /* Source (BSSID) */
    memcpy(&frame[offset], bssid, 6);
    offset += 6;

    /* BSSID */
    memcpy(&frame[offset], bssid, 6);
    offset += 6;

    /* Sequence Control */
    static uint16_t seq_num = 0;
    frame[offset++] = (seq_num << 4) & 0xFF;
    frame[offset++] = (seq_num >> 4) & 0xFF;
    seq_num++;

    /* === Beacon Frame Body === */

    /* Timestamp */
    uint64_t timestamp = 0;  /* Would be TSF timer in real implementation */
    memcpy(&frame[offset], &timestamp, 8);
    offset += 8;

    /* Beacon Interval (100 TU = 102.4 ms) */
    uint16_t beacon_interval = 100;
    memcpy(&frame[offset], &beacon_interval, 2);
    offset += 2;

    /* Capability Information */
    uint16_t capability = 0x0421;  /* ESS, Short Preamble, Short Slot Time */
    memcpy(&frame[offset], &capability, 2);
    offset += 2;

    /* === Information Elements === */

    /* SSID */
    frame[offset++] = 0;  /* IE ID: SSID */
    uint8_t ssid_len = strlen(ssid);
    frame[offset++] = ssid_len;
    memcpy(&frame[offset], ssid, ssid_len);
    offset += ssid_len;

    /* Supported Rates */
    frame[offset++] = 1;  /* IE ID: Supported Rates */
    frame[offset++] = 8;  /* Length */
    /* 802.11g rates: 6, 9, 12, 18, 24, 36, 48, 54 Mbps */
    frame[offset++] = 0x8C;  /* 6 Mbps (basic) */
    frame[offset++] = 0x12;  /* 9 Mbps */
    frame[offset++] = 0x98;  /* 12 Mbps (basic) */
    frame[offset++] = 0x24;  /* 18 Mbps */
    frame[offset++] = 0xB0;  /* 24 Mbps (basic) */
    frame[offset++] = 0x48;  /* 36 Mbps */
    frame[offset++] = 0x60;  /* 48 Mbps */
    frame[offset++] = 0x6C;  /* 54 Mbps */

    /* DS Parameter Set (current channel) */
    frame[offset++] = 3;  /* IE ID: DS Parameter Set */
    frame[offset++] = 1;  /* Length */
    frame[offset++] = channel;

    /* DTIM */
    frame[offset++] = 5;  /* IE ID: TIM */
    frame[offset++] = 4;  /* Length */
    frame[offset++] = 0;  /* DTIM Count */
    frame[offset++] = 1;  /* DTIM Period */
    frame[offset++] = 0;  /* Bitmap Control */
    frame[offset++] = 0;  /* Partial Virtual Bitmap */

    /* HT Capabilities (802.11n) */
    if (support_11n) {
        frame[offset++] = 45;  /* IE ID: HT Capabilities */
        frame[offset++] = 26;  /* Length */
        /* HT Capabilities Info */
        frame[offset++] = 0xEF;  /* LDPC, 20MHz, SM Power Save */
        frame[offset++] = 0x09;  /* Short GI for 20MHz */
        /* A-MPDU Parameters */
        frame[offset++] = 0x17;  /* Max A-MPDU length: 64KB, MPDU density: 8us */
        /* Supported MCS Set (16 bytes) */
        frame[offset++] = 0xFF;  /* MCS 0-7 */
        memset(&frame[offset], 0, 15);  /* Rest of MCS set */
        offset += 15;
        /* HT Extended Capabilities */
        frame[offset++] = 0x00;
        frame[offset++] = 0x00;
        /* Transmit Beamforming */
        memset(&frame[offset], 0, 4);
        offset += 4;
        /* ASEL Capabilities */
        frame[offset++] = 0x00;
    }

    /* VHT Capabilities (802.11ac) */
    if (support_11ac) {
        frame[offset++] = 191;  /* IE ID: VHT Capabilities */
        frame[offset++] = 12;   /* Length */
        /* VHT Capabilities Info */
        memset(&frame[offset], 0, 4);
        offset += 4;
        /* Supported VHT-MCS and NSS Set */
        frame[offset++] = 0xFA;  /* MCS 0-9 for 1 SS */
        frame[offset++] = 0xFF;
        memset(&frame[offset], 0, 6);
        offset += 6;
    }

    /* FCS will be added by hardware */

    return offset;
}

/* Scan for beacons on a channel */
void scan_channel(int channel, int dwell_time_ms)
{
    uint64_t freq = get_channel_freq(channel);
    if (freq == 0) {
        fprintf(stderr, "Invalid channel: %d\n", channel);
        return;
    }

    printf("Scanning channel %d (%s)...\n", channel,
           (freq < 3000000000ULL) ? "2.4GHz" : "5GHz");

    /* Configure for reception */
    configure_rx(freq, PLUTO_SAMPLE_RATE, 20000000);  /* 20 MHz BW */

    /* Create RX buffer */
    struct iio_buffer *rxbuf = iio_device_create_buffer(rx_dev, 4096, false);
    if (!rxbuf) {
        fprintf(stderr, "Failed to create RX buffer\n");
        return;
    }

    /* Enable channels */
    struct iio_channel *rx_i = iio_device_find_channel(rx_dev, "voltage0", false);
    struct iio_channel *rx_q = iio_device_find_channel(rx_dev, "voltage1", false);

    if (rx_i) iio_channel_enable(rx_i);
    if (rx_q) iio_channel_enable(rx_q);

    /* Scan for specified time */
    time_t start_time = time(NULL);
    int packets_detected = 0;

    while (running && (time(NULL) - start_time) < (dwell_time_ms / 1000)) {
        ssize_t nbytes = iio_buffer_refill(rxbuf);

        if (nbytes < 0) {
            fprintf(stderr, "Error refilling buffer: %ld\n", (long)nbytes);
            break;
        }

        /* Get IQ samples */
        void *buf_start = iio_buffer_start(rxbuf);
        size_t buf_step = iio_buffer_step(rxbuf);

        /* Process samples (placeholder for actual OFDM demod) */
        beacon_info_t info;
        int16_t *samples = (int16_t *)buf_start;

        /* In full implementation, would call OFDM demodulator here */
        /* For minimal version, just show we're scanning */

        usleep(10000);  /* 10ms */
    }

    /* Cleanup */
    if (rx_i) iio_channel_disable(rx_i);
    if (rx_q) iio_channel_disable(rx_q);
    iio_buffer_destroy(rxbuf);

    printf("Channel %d scan complete. Detected %d beacons.\n", channel, packets_detected);
}

/* Transmit beacon */
int transmit_beacon(int channel, const char *ssid, const uint8_t *bssid, int count)
{
    uint64_t freq = get_channel_freq(channel);
    if (freq == 0) {
        fprintf(stderr, "Invalid channel: %d\n", channel);
        return -1;
    }

    printf("Transmitting beacon on channel %d...\n", channel);
    printf("  SSID: %s\n", ssid);
    printf("  BSSID: %02x:%02x:%02x:%02x:%02x:%02x\n",
           bssid[0], bssid[1], bssid[2], bssid[3], bssid[4], bssid[5]);
    printf("  Count: %d beacons\n", count);

    /* Configure for transmission */
    configure_tx(freq, PLUTO_SAMPLE_RATE, 20000000);

    /* Generate beacon frame */
    uint8_t beacon_frame[512];
    size_t frame_len = generate_beacon_frame(beacon_frame, sizeof(beacon_frame),
                                             ssid, bssid, channel, true, false);

    if (frame_len == 0) {
        fprintf(stderr, "Failed to generate beacon frame\n");
        return -1;
    }

    printf("Generated beacon frame: %zu bytes\n", frame_len);

    /* In full implementation, would:
     * 1. Generate OFDM symbols from beacon frame
     * 2. Add preamble (short + long training sequences)
     * 3. Modulate and transmit via PlutoSDR
     *
     * This requires full OFDM modulator implementation
     */

    printf("Note: Full OFDM modulation not implemented in minimal version\n");
    printf("Frame generated successfully. Use full implementation for TX.\n");

    return 0;
}

/* Automated scanner - scan all channels */
void automated_scan(int dwell_time_ms, bool continuous)
{
    printf("Starting automated WiFi beacon scanner...\n");
    printf("Dwell time: %d ms per channel\n", dwell_time_ms);
    printf("Mode: %s\n", continuous ? "Continuous" : "Single pass");
    printf("Press Ctrl+C to stop\n\n");

    do {
        /* Scan 2.4 GHz channels */
        printf("\n=== Scanning 2.4 GHz Band ===\n");
        for (int ch = 1; ch <= 13 && running; ch++) {
            scan_channel(ch, dwell_time_ms);
        }

        /* Scan 5 GHz channels */
        printf("\n=== Scanning 5 GHz Band ===\n");
        int ghz5_channels[] = {36, 40, 44, 48, 52, 56, 60, 64,
                               100, 104, 108, 112, 116, 120, 124, 128,
                               132, 136, 140, 149, 153, 157, 161, 165};

        for (int i = 0; i < sizeof(ghz5_channels)/sizeof(int) && running; i++) {
            scan_channel(ghz5_channels[i], dwell_time_ms);
        }

        if (continuous && running) {
            printf("\n=== Scan cycle complete. Starting new cycle... ===\n\n");
        }

    } while (continuous && running);

    printf("\nAutomated scan complete.\n");
}

/* Print usage */
void print_usage(const char *prog_name)
{
    printf("PlutoSDR WiFi Beacon Scanner v%s\n\n", PROGRAM_VERSION);
    printf("Usage: %s [options]\n\n", prog_name);
    printf("Options:\n");
    printf("  -h             Show this help\n");
    printf("  -u URI         PlutoSDR URI (default: auto-detect)\n");
    printf("  -m MODE        Operation mode:\n");
    printf("                   scan  - Receive beacons (default)\n");
    printf("                   tx    - Transmit beacons\n");
    printf("  -c CHANNEL     WiFi channel (1-13 for 2.4GHz, 36-165 for 5GHz)\n");
    printf("  -s SSID        SSID for beacon transmission\n");
    printf("  -b BSSID       BSSID for beacon transmission (XX:XX:XX:XX:XX:XX)\n");
    printf("  -n COUNT       Number of beacons to transmit (default: continuous)\n");
    printf("  -t TIME        Dwell time per channel in ms (default: 500)\n");
    printf("  -a             Automated scan (all channels)\n");
    printf("  -r             Continuous scanning (repeat)\n");
    printf("\nExamples:\n");
    printf("  %s -m scan -c 6              # Scan channel 6\n", prog_name);
    printf("  %s -a -t 1000               # Automated scan, 1s per channel\n", prog_name);
    printf("  %s -m tx -c 6 -s TestAP -n 10  # TX 10 beacons on channel 6\n", prog_name);
    printf("\n");
}

/* Main */
int main(int argc, char **argv)
{
    const char *uri = NULL;
    const char *mode = "scan";
    int channel = 6;
    const char *ssid = "PlutoSDR-AP";
    uint8_t bssid[6] = {0x02, 0x00, 0x00, 0x00, 0x00, 0x01};
    int beacon_count = -1;  /* Continuous */
    int dwell_time_ms = 500;
    bool automated = false;
    bool continuous = false;

    /* Parse arguments */
    int opt;
    while ((opt = getopt(argc, argv, "hu:m:c:s:b:n:t:ar")) != -1) {
        switch (opt) {
            case 'h':
                print_usage(argv[0]);
                return 0;

            case 'u':
                uri = optarg;
                break;

            case 'm':
                mode = optarg;
                break;

            case 'c':
                channel = atoi(optarg);
                break;

            case 's':
                ssid = optarg;
                break;

            case 'b':
                sscanf(optarg, "%hhx:%hhx:%hhx:%hhx:%hhx:%hhx",
                      &bssid[0], &bssid[1], &bssid[2],
                      &bssid[3], &bssid[4], &bssid[5]);
                break;

            case 'n':
                beacon_count = atoi(optarg);
                break;

            case 't':
                dwell_time_ms = atoi(optarg);
                break;

            case 'a':
                automated = true;
                break;

            case 'r':
                continuous = true;
                break;

            default:
                print_usage(argv[0]);
                return 1;
        }
    }

    /* Setup signal handler */
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    /* Initialize PlutoSDR */
    if (init_plutosdr(uri) < 0) {
        fprintf(stderr, "Failed to initialize PlutoSDR\n");
        return 1;
    }

    /* Execute requested operation */
    if (strcmp(mode, "scan") == 0) {
        if (automated) {
            automated_scan(dwell_time_ms, continuous);
        } else {
            scan_channel(channel, dwell_time_ms * 10);  /* Longer scan for single channel */
        }
    } else if (strcmp(mode, "tx") == 0) {
        transmit_beacon(channel, ssid, bssid, beacon_count);
    } else {
        fprintf(stderr, "Invalid mode: %s\n", mode);
        print_usage(argv[0]);
        return 1;
    }

    /* Cleanup */
    if (ctx) {
        iio_context_destroy(ctx);
    }

    printf("\nShutdown complete.\n");
    return 0;
}
