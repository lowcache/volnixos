// Unit tests for chordgate's chord state machine and key-file handling; run at build time.
#define CHORDGATE_TEST
#include "chordgate.c"

static int failed;
#define CHECK(x)                                                        \
	do {                                                            \
		if (!(x)) {                                             \
			fprintf(stderr, "%s:%d: %s\n", __func__, __LINE__, #x); \
			failed = 1;                                     \
		}                                                       \
	} while (0)

static struct chord c;
static void reset(void) { memset(&c, 0, sizeof c); }
static int P(unsigned k) { return chord_feed(&c, EV_KEY, k, 1); }
static int R(unsigned k) { return chord_feed(&c, EV_KEY, k, 0); }
static int tap(unsigned k)
{
	int r = P(k);
	return r == MORE ? R(k) : r;
}

static struct chord held; /* Ctrl+Shift held through e,n,c,f */

static void test_held(void)
{
	reset();
	P(KEY_LEFTCTRL);
	P(KEY_LEFTSHIFT);
	tap(KEY_E), tap(KEY_N), tap(KEY_C), tap(KEY_F);
	CHECK(R(KEY_LEFTSHIFT) == MORE);
	CHECK(R(KEY_LEFTCTRL) == DONE);
	CHECK(c.n == 4);
	CHECK(c.buf[0] == 3 && c.buf[1] == KEY_E && c.buf[2] == 0);
	CHECK(c.buf[9] == 3 && c.buf[10] == KEY_F);
	held = c;
}

static void test_press_release_differs(void)
{
	reset();
	P(KEY_LEFTCTRL);
	P(KEY_LEFTSHIFT);
	tap(KEY_E);
	R(KEY_LEFTSHIFT);
	CHECK(R(KEY_LEFTCTRL) == DONE);
	CHECK(c.n == 1);
	CHECK(c.n != held.n);
}

static void test_left_right_merge(void)
{
	reset();
	P(KEY_RIGHTCTRL);
	P(KEY_RIGHTSHIFT);
	tap(KEY_E), tap(KEY_N), tap(KEY_C), tap(KEY_F);
	R(KEY_RIGHTCTRL);
	CHECK(R(KEY_RIGHTSHIFT) == DONE);
	CHECK(c.n == held.n && !memcmp(c.buf, held.buf, 3 * (size_t)c.n));
}

static void test_mid_chord_change(void)
{
	reset();
	P(KEY_LEFTCTRL);
	P(KEY_LEFTSHIFT);
	tap(KEY_E);
	CHECK(R(KEY_LEFTSHIFT) == MORE); /* Ctrl still held */
	P(KEY_LEFTALT);
	tap(KEY_F);
	R(KEY_LEFTALT);
	CHECK(R(KEY_LEFTCTRL) == DONE);
	CHECK(c.n == 2 && c.buf[0] == 3 && c.buf[3] == 5);
}

static void test_super_mask(void)
{
	reset();
	P(KEY_RIGHTMETA);
	tap(KEY_1);
	CHECK(R(KEY_RIGHTMETA) == DONE);
	CHECK(c.buf[0] == 8 && c.buf[1] == KEY_1);
}

static void test_autorepeat_ignored(void)
{
	reset();
	P(KEY_LEFTCTRL);
	P(KEY_E);
	for (int i = 0; i < 3; i++)
		chord_feed(&c, EV_KEY, KEY_E, 2);
	R(KEY_E);
	CHECK(R(KEY_LEFTCTRL) == DONE);
	CHECK(c.n == 1);
}

static void test_keys_before_modifiers_ignored(void)
{
	reset();
	tap(KEY_X);
	tap(KEY_ENTER);
	CHECK(c.n == 0);
	P(KEY_LEFTCTRL);
	tap(KEY_E);
	CHECK(R(KEY_LEFTCTRL) == DONE);
	CHECK(c.n == 1 && c.buf[1] == KEY_E);
}

static void test_zero_step_release_resets(void)
{
	reset();
	P(KEY_LEFTCTRL);
	CHECK(R(KEY_LEFTCTRL) == MORE);
	CHECK(c.n == 0);
}

static void test_both_shifts(void)
{
	reset();
	P(KEY_LEFTSHIFT);
	P(KEY_RIGHTSHIFT);
	CHECK(R(KEY_LEFTSHIFT) == MORE);
	tap(KEY_E);
	CHECK(c.buf[0] == 2);
	CHECK(R(KEY_RIGHTSHIFT) == DONE);
}

static void test_overflow(void)
{
	reset();
	P(KEY_LEFTCTRL);
	for (int i = 0; i < MAX_STEPS; i++)
		CHECK(tap(KEY_A) == MORE);
	CHECK(P(KEY_A) == OVERFLOW);
}

static void test_non_keys_ignored(void)
{
	reset();
	P(KEY_LEFTCTRL);
	tap(BTN_LEFT);
	chord_feed(&c, EV_MSC, MSC_SCAN, 30);
	chord_feed(&c, EV_SYN, SYN_REPORT, 0);
	CHECK(c.n == 0);
}

static void test_files(void)
{
	const char *base = getenv("TMPDIR");
	char dir[4096], dev[4200], key[4200];
	snprintf(dir, sizeof dir, "%s/chordgate-test.XXXXXX", base ? base : "/tmp");
	if (!mkdtemp(dir)) {
		CHECK(!"mkdtemp");
		return;
	}
	snprintf(dev, sizeof dev, "%s/stick", dir);
	snprintf(key, sizeof key, "%s/keys/k.key", dir);
	long long off = 3 * 4096 + 17;

	int fd = open(dev, O_RDWR | O_CREAT, 0600);
	CHECK(fd >= 0 && !ftruncate(fd, 1 << 20));
	uint8_t blob[BLOB_LEN], got[BLOB_LEN];
	CHECK(read_blob(dev, off, got) == -1); /* all zeros = not enrolled */
	for (int i = 0; i < BLOB_LEN; i++)
		blob[i] = (uint8_t)(i * 7 + 1);
	CHECK(pwrite(fd, blob, BLOB_LEN, off) == BLOB_LEN);
	close(fd);
	CHECK(read_blob(dev, off, got) == 0 && !memcmp(blob, got, BLOB_LEN));
	CHECK(read_blob(dev, (1 << 20) - 10, got) == -1); /* short read */
	CHECK(read_blob("/nonexistent/stick", 0, got) == -1);

	CHECK(write_key(key, blob, &held) == 0);
	struct stat st;
	CHECK(!stat(key, &st) && st.st_size == BLOB_LEN + 3 * held.n && (st.st_mode & 0777) == 0400);
	uint8_t buf[BLOB_LEN + MAX_STEPS * 3];
	fd = open(key, O_RDONLY);
	CHECK(fd >= 0 && read(fd, buf, sizeof buf) == st.st_size);
	close(fd);
	CHECK(!memcmp(buf, blob, BLOB_LEN) && !memcmp(buf + BLOB_LEN, held.buf, 3 * (size_t)held.n));
	CHECK(write_key(key, blob, &held) == 0); /* overwrites an existing key */

	CHECK(wipe(key) == 0 && access(key, F_OK) == -1);
	CHECK(wipe(key) == 0); /* missing file is fine */
	CHECK(wait_for(dev, 0) == 0 && wait_for(key, 0) == -1);

	unlink(dev);
	snprintf(key, sizeof key, "%s/keys", dir);
	rmdir(key);
	rmdir(dir);
}

int main(void)
{
	test_held();
	test_press_release_differs();
	test_left_right_merge();
	test_mid_chord_change();
	test_super_mask();
	test_autorepeat_ignored();
	test_keys_before_modifiers_ignored();
	test_zero_step_release_resets();
	test_both_shifts();
	test_overflow();
	test_non_keys_ignored();
	test_files();
	puts(failed ? "FAIL" : "ok");
	return failed;
}
