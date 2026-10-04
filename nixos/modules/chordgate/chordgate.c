// chordgate: LUKS keyfile = 64-byte blob from a USB stick ‖ a held-modifier key chord.
// `boot` never fails the boot (no key → systemd-cryptsetup prompts); `enroll` captures twice.
#define _GNU_SOURCE
#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <getopt.h>
#include <linux/input.h>
#include <poll.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define BLOB_LEN 64
#define MAX_STEPS 64
#define MIN_ENROLL_STEPS 8
#define MAX_DEVS 32
#define TICK_MS 500

enum { MORE, DONE, OVERFLOW };

struct chord {
	unsigned modkeys; /* one bit per physical modifier key */
	int n;
	uint8_t buf[MAX_STEPS * 3]; /* per step: mask, keycode lo, keycode hi */
};

static const unsigned modcodes[8] = {
	KEY_LEFTCTRL, KEY_RIGHTCTRL, KEY_LEFTSHIFT, KEY_RIGHTSHIFT,
	KEY_LEFTALT,  KEY_RIGHTALT,  KEY_LEFTMETA,  KEY_RIGHTMETA,
};

static int mod_index(unsigned code)
{
	for (int i = 0; i < 8; i++)
		if (modcodes[i] == code)
			return i;
	return -1;
}

/* Left/right merged: bit0 Ctrl, bit1 Shift, bit2 Alt, bit3 Super. */
static uint8_t mod_mask(unsigned modkeys)
{
	uint8_t m = 0;
	for (int i = 0; i < 4; i++)
		if (modkeys & (3u << (2 * i)))
			m |= 1u << i;
	return m;
}

static int chord_feed(struct chord *c, unsigned type, unsigned code, int value)
{
	if (type != EV_KEY || value == 2)
		return MORE;
	int i = mod_index(code);
	if (i >= 0) {
		if (value)
			c->modkeys |= 1u << i;
		else
			c->modkeys &= ~(1u << i);
		return (!c->modkeys && c->n) ? DONE : MORE;
	}
	if (!value || code >= BTN_MISC || !c->modkeys)
		return MORE;
	if (c->n == MAX_STEPS)
		return OVERFLOW;
	uint8_t *p = c->buf + 3 * c->n++;
	p[0] = mod_mask(c->modkeys);
	p[1] = code & 0xff;
	p[2] = code >> 8;
	return MORE;
}

/* ---- evdev ---- */

struct kbd {
	int fd, led0, dead;
	char name[32];
};
static struct kbd kbds[MAX_DEVS];
static int nkbd;
static volatile sig_atomic_t stop;

#define LONGBITS (8 * sizeof(long))
static int test_bit(const unsigned long *bits, int b)
{
	return (bits[b / LONGBITS] >> (b % LONGBITS)) & 1;
}

static long now_ms(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec * 1000L + t.tv_nsec / 1000000;
}

static void set_led(struct kbd *k, int on)
{
	struct input_event ev[2];
	memset(ev, 0, sizeof ev);
	ev[0].type = EV_LED;
	ev[0].code = LED_CAPSL;
	ev[0].value = on;
	ev[1].type = EV_SYN;
	ev[1].code = SYN_REPORT;
	if (write(k->fd, ev, sizeof ev) < 0) {
		/* LED is cosmetic */
	}
}

/* Open + grab every keyboard not already held; called each tick to catch late devices. */
static void scan_keyboards(void)
{
	DIR *d = opendir("/dev/input");
	if (!d)
		return;
	struct dirent *e;
	while ((e = readdir(d)) && nkbd < MAX_DEVS) {
		if (strncmp(e->d_name, "event", 5))
			continue;
		int seen = 0;
		for (int i = 0; i < nkbd; i++)
			seen |= !strcmp(kbds[i].name, e->d_name);
		if (seen)
			continue;
		char path[300];
		snprintf(path, sizeof path, "/dev/input/%s", e->d_name);
		int fd = open(path, O_RDWR | O_NONBLOCK | O_CLOEXEC);
		if (fd < 0)
			continue;
		unsigned long keys[KEY_CNT / LONGBITS + 1] = { 0 };
		if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof keys), keys) < 0 ||
		    !test_bit(keys, KEY_A) || !test_bit(keys, KEY_LEFTCTRL)) {
			close(fd);
			continue;
		}
		unsigned long leds[LED_CNT / LONGBITS + 1] = { 0 };
		ioctl(fd, EVIOCGLED(sizeof leds), leds);
		ioctl(fd, EVIOCGRAB, 1); /* keystrokes never reach the console */
		struct kbd *k = &kbds[nkbd++];
		k->fd = fd;
		k->dead = 0;
		k->led0 = test_bit(leds, LED_CAPSL);
		snprintf(k->name, sizeof k->name, "%.31s", e->d_name);
	}
	closedir(d);
}

static void drop_dead(void)
{
	for (int i = 0; i < nkbd;) {
		if (kbds[i].dead) {
			close(kbds[i].fd);
			kbds[i] = kbds[--nkbd];
		} else {
			i++;
		}
	}
}

static void release_keyboards(void)
{
	for (int i = 0; i < nkbd; i++) {
		set_led(&kbds[i], kbds[i].led0);
		ioctl(kbds[i].fd, EVIOCGRAB, 0);
		close(kbds[i].fd);
	}
	nkbd = 0;
}

/* Blink Caps Lock and record one chord. 0 = chord captured; -1 = timeout/overflow/signal. */
static int capture(struct chord *c, int timeout_s)
{
	memset(c, 0, sizeof *c);
	long deadline = now_ms() + timeout_s * 1000L, next_tick = 0;
	int led = 0, r = MORE;
	while (r == MORE && !stop) {
		long t = now_ms();
		if (t >= deadline)
			break;
		if (t >= next_tick) {
			drop_dead();
			scan_keyboards();
			led = !led;
			for (int i = 0; i < nkbd; i++)
				set_led(&kbds[i], led);
			next_tick = t + TICK_MS;
		}
		struct pollfd p[MAX_DEVS];
		for (int i = 0; i < nkbd; i++)
			p[i] = (struct pollfd){ .fd = kbds[i].fd, .events = POLLIN };
		long wait = (next_tick < deadline ? next_tick : deadline) - t;
		if (poll(p, nkbd, (int)wait) < 0)
			continue; /* EINTR: loop re-checks stop */
		for (int i = 0; i < nkbd && r == MORE; i++) {
			if (p[i].revents & (POLLERR | POLLHUP | POLLNVAL)) {
				kbds[i].dead = 1;
				continue;
			}
			if (!(p[i].revents & POLLIN))
				continue;
			struct input_event ev[64];
			ssize_t n;
			while (r == MORE && (n = read(kbds[i].fd, ev, sizeof ev)) > 0)
				for (size_t j = 0; j < (size_t)n / sizeof *ev && r == MORE; j++)
					r = chord_feed(c, ev[j].type, ev[j].code, ev[j].value);
			if (n < 0 && errno != EAGAIN)
				kbds[i].dead = 1;
		}
	}
	release_keyboards();
	return r == DONE ? 0 : -1;
}

/* ---- files ---- */

static int wait_for(const char *path, int secs)
{
	long deadline = now_ms() + secs * 1000L;
	for (;;) {
		if (!access(path, F_OK))
			return 0;
		if (now_ms() >= deadline || stop)
			return -1;
		usleep(250 * 1000);
	}
}

/* All-zero blob = stick never enrolled. */
static int read_blob(const char *dev, long long off, uint8_t *blob)
{
	int fd = open(dev, O_RDONLY | O_CLOEXEC);
	if (fd < 0)
		return -1;
	ssize_t n = pread(fd, blob, BLOB_LEN, off);
	close(fd);
	if (n != BLOB_LEN)
		return -1;
	for (int i = 0; i < BLOB_LEN; i++)
		if (blob[i])
			return 0;
	return -1;
}

static int wipe(const char *path)
{
	chmod(path, 0600);
	int fd = open(path, O_WRONLY | O_CLOEXEC | O_NOFOLLOW);
	if (fd < 0)
		return errno == ENOENT ? 0 : -1;
	struct stat st;
	if (!fstat(fd, &st)) {
		static const uint8_t z[4096];
		for (off_t o = 0; o < st.st_size; o += sizeof z) {
			size_t len = st.st_size - o < (off_t)sizeof z ? (size_t)(st.st_size - o) : sizeof z;
			if (pwrite(fd, z, len, o) < 0)
				break;
		}
		fsync(fd);
	}
	close(fd);
	return unlink(path);
}

static int write_key(const char *out, const uint8_t *blob, const struct chord *c)
{
	char dir[4096];
	snprintf(dir, sizeof dir, "%s", out);
	char *slash = strrchr(dir, '/');
	if (slash && slash != dir) {
		*slash = 0;
		if (mkdir(dir, 0700) && errno != EEXIST)
			return -1;
	}
	if (wipe(out))
		return -1;
	int fd = open(out, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0400);
	if (fd < 0)
		return -1;
	size_t clen = 3 * (size_t)c->n;
	int ok = write(fd, blob, BLOB_LEN) == BLOB_LEN && write(fd, c->buf, clen) == (ssize_t)clen &&
		 !fsync(fd);
	close(fd);
	if (!ok) {
		wipe(out);
		return -1;
	}
	return 0;
}

#ifndef CHORDGATE_TEST

static void on_signal(int sig)
{
	(void)sig;
	stop = 1;
}

static void usage(void)
{
	fputs("usage: chordgate boot|enroll --device PATH --offset BYTES --out FILE"
	      " [--stick-wait S] [--timeout S]\n"
	      "       chordgate wipe FILE\n",
	      stderr);
	exit(2);
}

int main(int argc, char **argv)
{
	if (argc < 2)
		usage();
	if (!strcmp(argv[1], "wipe")) {
		if (argc != 3)
			usage();
		return wipe(argv[2]) ? 1 : 0;
	}
	int boot = !strcmp(argv[1], "boot");
	if (!boot && strcmp(argv[1], "enroll"))
		usage();

	const char *dev = NULL, *out = NULL;
	long long off = -1;
	int stick_wait = 10, timeout = 60, o;
	static const struct option opts[] = {
		{ "device", required_argument, 0, 'd' },     { "offset", required_argument, 0, 'o' },
		{ "out", required_argument, 0, 'f' },        { "stick-wait", required_argument, 0, 'w' },
		{ "timeout", required_argument, 0, 't' },    { 0, 0, 0, 0 },
	};
	optind = 2;
	while ((o = getopt_long(argc, argv, "", opts, NULL)) != -1) {
		switch (o) {
		case 'd': dev = optarg; break;
		case 'o': off = atoll(optarg); break;
		case 'f': out = optarg; break;
		case 'w': stick_wait = atoi(optarg); break;
		case 't': timeout = atoi(optarg); break;
		default: usage();
		}
	}
	if (!dev || !out || off < 0)
		usage();

	struct sigaction sa = { .sa_handler = on_signal };
	sigaction(SIGTERM, &sa, NULL);
	sigaction(SIGINT, &sa, NULL);

	uint8_t blob[BLOB_LEN];
	struct chord a, b;
	if (boot) {
		if (wait_for(dev, stick_wait)) {
			fputs("chordgate: no stick\n", stderr);
			return 0;
		}
		if (read_blob(dev, off, blob)) {
			fputs("chordgate: no blob on stick\n", stderr);
			return 0;
		}
		if (capture(&a, timeout)) {
			fputs("chordgate: no chord\n", stderr);
			return 0;
		}
		if (write_key(out, blob, &a))
			perror("chordgate: write key");
		else
			fputs("chordgate: key ready\n", stderr);
		return 0;
	}

	if (read_blob(dev, off, blob)) {
		fputs("chordgate: no blob on stick (write it first)\n", stderr);
		return 1;
	}
	fputs("Caps Lock blinks: hold modifiers, type the chord, release all modifiers.\n", stderr);
	if (capture(&a, timeout)) {
		fputs("chordgate: no chord captured\n", stderr);
		return 1;
	}
	if (a.n < MIN_ENROLL_STEPS) {
		fprintf(stderr, "chordgate: %d keys; need at least %d\n", a.n, MIN_ENROLL_STEPS);
		return 1;
	}
	fputs("Again, to confirm.\n", stderr);
	if (capture(&b, timeout)) {
		fputs("chordgate: no chord captured\n", stderr);
		return 1;
	}
	if (a.n != b.n || memcmp(a.buf, b.buf, 3 * (size_t)a.n)) {
		fputs("chordgate: chords did not match\n", stderr);
		return 1;
	}
	if (write_key(out, blob, &a)) {
		perror("chordgate: write key");
		return 1;
	}
	fprintf(stderr, "chordgate: %d-key chord captured\n", a.n);
	return 0;
}

#endif
