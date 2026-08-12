/* Build-time leak-detection switch (SPEC §6.2 item 15). Linked into every ASan fuzz binary
 * through the rustc linker wrapper in mayhem/build.sh. ASan stays fully active; only
 * LeakSanitizer is turned off. */
int __lsan_is_turned_off(void) { return 1; }
