/**
 * @file gpio_blink.c
 * @brief VSync GPIO LED blink example
 *
 * Demonstrates GPIO output control using the VSync POSIX API.
 * Toggles an LED on/off in an infinite loop with nanosleep delays.
 */

#include "../lib/vsync_posix.h"

/** LED output bit position */
#define LED_BIT  0x01

/**
 * @brief Main entry point
 *
 * Opens GPIO device, configures direction as output, and
 * blinks LED in an infinite loop with 500ms interval.
 *
 * @return Does not return (infinite loop)
 */
int main(void)
{
    int fd;
    unsigned long led_state = 0;

    /* Open GPIO device */
    fd = open(FD_TYPE_GPIO, 0);
    if (fd < 0) {
        return -1;
    }

    /* Configure GPIO pin as output */
    ioctl(fd, GPIO_SET_DIR, LED_BIT);

    /* 500ms delay specification */
    timespec_t delay;
    delay.tv_sec  = 0;
    delay.tv_nsec = 500000000L;  /* 500ms */

    /* Infinite blink loop */
    while (1) {
        /* Toggle LED state */
        led_state ^= LED_BIT;

        /* Write LED state to GPIO */
        ioctl(fd, GPIO_SET_OUTPUT, led_state);

        /* Wait 500ms */
        nanosleep(&delay, NULL);
    }

    /* Never reached */
    close(fd);
    return 0;
}
