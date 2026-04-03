/**
 * @file vsync_posix.h
 * @brief VSync POSIX-compatible C library header
 *
 * Provides POSIX-like API for the VSync hardware RTOS processor.
 * Syscall numbers correspond to vsync_pkg.sv definitions.
 */

#ifndef VSYNC_POSIX_H
#define VSYNC_POSIX_H

#include <stdint.h>
#include <stddef.h>

/* =========================================================================
 * Type Definitions
 * ========================================================================= */

/** Thread ID type */
typedef uint32_t pthread_t;

/** Thread attributes (placeholder) */
typedef struct {
    uint32_t stack_size;
    uint32_t priority;
    uint32_t detach_state;
} pthread_attr_t;

/** Mutex type */
typedef uint32_t pthread_mutex_t;

/** Mutex attributes (placeholder) */
typedef uint32_t pthread_mutexattr_t;

/** Semaphore type */
typedef uint32_t sem_t;

/** Message queue descriptor */
typedef int32_t mqd_t;

/** Message queue attributes */
typedef struct {
    long mq_flags;
    long mq_maxmsg;
    long mq_msgsize;
    long mq_curmsgs;
} mq_attr_t;

/** Time specification */
typedef struct {
    long tv_sec;
    long tv_nsec;
} timespec_t;

/** Clock ID type */
typedef int32_t clockid_t;

/** Scheduling parameters */
typedef struct {
    int sched_priority;
} sched_param_t;

/** File descriptor type constants */
#define FD_TYPE_NONE   0
#define FD_TYPE_UART   1
#define FD_TYPE_GPIO   2
#define FD_TYPE_MEM    3
#define FD_TYPE_PIPE   4

/** Clock IDs */
#define CLOCK_REALTIME           0
#define CLOCK_MONOTONIC          1

/** Open flags */
#define O_RDONLY    0x0000
#define O_WRONLY    0x0001
#define O_RDWR     0x0002
#define O_CREAT    0x0040
#define O_TRUNC    0x0200
#define O_APPEND   0x0400

/** ioctl commands for GPIO (values must match APB register offsets in gpio_apb.sv) */
#define GPIO_SET_OUTPUT  0x00    /* REG_GPIO_OUT  (offset 0x00) - Write output register  */
#define GPIO_GET_INPUT   0x04   /* REG_GPIO_IN   (offset 0x04) - Read input register    */
#define GPIO_SET_DIR     0x08   /* REG_GPIO_DIR  (offset 0x08) - Set direction (1=output) */

/** Error codes */
#define ENOMEM     12
#define EINVAL     22
#define EAGAIN     11
#define EBUSY      16
#define ETIMEDOUT  110
#define ENOSYS     38
#define EBADF       9

/** NULL definition */
#ifndef NULL
#define NULL ((void *)0)
#endif

/* =========================================================================
 * Syscall Numbers (from vsync_pkg.sv)
 * ========================================================================= */

/* Thread Management (0x00-0x07) */
#define SYS_PTHREAD_CREATE        0x00
#define SYS_PTHREAD_EXIT          0x01
#define SYS_PTHREAD_JOIN          0x02
#define SYS_PTHREAD_DETACH        0x03
#define SYS_PTHREAD_SELF          0x04
#define SYS_PTHREAD_YIELD         0x05
#define SYS_PTHREAD_SETSCHEDPARAM 0x06
#define SYS_PTHREAD_GETSCHEDPARAM 0x07

/* Mutex Operations (0x10-0x14) */
#define SYS_MUTEX_INIT            0x10
#define SYS_MUTEX_LOCK            0x11
#define SYS_MUTEX_TRYLOCK         0x12
#define SYS_MUTEX_UNLOCK          0x13
#define SYS_MUTEX_DESTROY         0x14

/* Semaphore Operations (0x20-0x26) */
#define SYS_SEM_INIT              0x20
#define SYS_SEM_WAIT              0x21
#define SYS_SEM_TRYWAIT           0x22
#define SYS_SEM_TIMEDWAIT         0x23
#define SYS_SEM_POST              0x24
#define SYS_SEM_GETVALUE          0x25
#define SYS_SEM_DESTROY           0x26

/* Message Queue Operations (0x30-0x35) */
#define SYS_MQ_OPEN               0x30
#define SYS_MQ_SEND               0x31
#define SYS_MQ_RECEIVE            0x32
#define SYS_MQ_CLOSE              0x33
#define SYS_MQ_TIMEDRECEIVE       0x34
#define SYS_MQ_TIMEDSEND          0x35

/* Timer/Clock Operations (0x40-0x46) */
#define SYS_CLOCK_GETTIME         0x40
#define SYS_CLOCK_SETTIME         0x41
#define SYS_NANOSLEEP             0x42
#define SYS_TIMER_CREATE          0x43
#define SYS_TIMER_SETTIME         0x44
#define SYS_TIMER_DELETE          0x45
#define SYS_TIMER_GETTIME         0x46

/* File I/O Operations (0x50-0x55) */
#define SYS_OPEN                  0x50
#define SYS_CLOSE                 0x51
#define SYS_READ                  0x52
#define SYS_WRITE                 0x53
#define SYS_IOCTL                 0x54
#define SYS_LSEEK                 0x55

/* =========================================================================
 * Syscall Inline Functions
 * ========================================================================= */

/**
 * @brief Issue a syscall with no arguments
 * @param num Syscall number
 * @return Syscall return value
 */
static inline long syscall0(long num) {
    register long a7 __asm__("a7") = num;
    register long a0 __asm__("a0");
    __asm__ volatile("ecall"
        : "=r"(a0)
        : "r"(a7)
        : "memory");
    return a0;
}

/**
 * @brief Issue a syscall with 1 argument
 * @param num Syscall number
 * @param a0 First argument
 * @return Syscall return value
 */
static inline long syscall1(long num, long a0) {
    register long _a7 __asm__("a7") = num;
    register long _a0 __asm__("a0") = a0;
    __asm__ volatile("ecall"
        : "+r"(_a0)
        : "r"(_a7)
        : "memory");
    return _a0;
}

/**
 * @brief Issue a syscall with 2 arguments
 * @param num Syscall number
 * @param a0 First argument
 * @param a1 Second argument
 * @return Syscall return value
 */
static inline long syscall2(long num, long a0, long a1) {
    register long _a7 __asm__("a7") = num;
    register long _a0 __asm__("a0") = a0;
    register long _a1 __asm__("a1") = a1;
    __asm__ volatile("ecall"
        : "+r"(_a0)
        : "r"(_a7), "r"(_a1)
        : "memory");
    return _a0;
}

/**
 * @brief Issue a syscall with 3 arguments
 * @param num Syscall number
 * @param a0 First argument
 * @param a1 Second argument
 * @param a2 Third argument
 * @return Syscall return value
 */
static inline long syscall3(long num, long a0, long a1, long a2) {
    register long a7 __asm__("a7") = num;
    register long _a0 __asm__("a0") = a0;
    register long _a1 __asm__("a1") = a1;
    register long _a2 __asm__("a2") = a2;
    __asm__ volatile("ecall"
        : "+r"(_a0)
        : "r"(a7), "r"(_a1), "r"(_a2)
        : "memory");
    return _a0;
}

/**
 * @brief Issue a syscall with 4 arguments
 * @param num Syscall number
 * @param a0 First argument
 * @param a1 Second argument
 * @param a2 Third argument
 * @param a3 Fourth argument
 * @return Syscall return value
 */
static inline long syscall4(long num, long a0, long a1, long a2, long a3) {
    register long a7 __asm__("a7") = num;
    register long _a0 __asm__("a0") = a0;
    register long _a1 __asm__("a1") = a1;
    register long _a2 __asm__("a2") = a2;
    register long _a3 __asm__("a3") = a3;
    __asm__ volatile("ecall"
        : "+r"(_a0)
        : "r"(a7), "r"(_a1), "r"(_a2), "r"(_a3)
        : "memory");
    return _a0;
}

/* =========================================================================
 * Thread Management API
 * ========================================================================= */

/**
 * @brief Create a new thread
 * @param thread Pointer to thread ID (output)
 * @param attr Thread attributes (may be NULL)
 * @param start_routine Thread entry function
 * @param arg Argument to pass to start_routine
 * @return 0 on success, error code on failure
 */
int pthread_create(pthread_t *thread, const pthread_attr_t *attr,
                   void *(*start_routine)(void *), void *arg);

/**
 * @brief Terminate the calling thread
 * @param retval Return value (passed to joining thread)
 */
void pthread_exit(void *retval);

/**
 * @brief Yield the processor to another thread
 * @return 0 on success
 */
int pthread_yield(void);

/**
 * @brief Get the calling thread's ID
 * @return Thread ID of the calling thread
 */
pthread_t pthread_self(void);

/**
 * @brief Wait for a thread to terminate
 * @param thread Thread ID to wait for
 * @param retval Pointer to store the return value (may be NULL)
 * @return 0 on success, error code on failure
 */
int pthread_join(pthread_t thread, void **retval);

/**
 * @brief Detach a thread
 * @param thread Thread ID to detach
 * @return 0 on success, error code on failure
 */
int pthread_detach(pthread_t thread);

/* =========================================================================
 * Mutex API
 * ========================================================================= */

/**
 * @brief Initialize a mutex
 * @param mutex Pointer to mutex
 * @param attr Mutex attributes (may be NULL)
 * @return 0 on success, error code on failure
 */
int pthread_mutex_init(pthread_mutex_t *mutex, const pthread_mutexattr_t *attr);

/**
 * @brief Lock a mutex (blocking)
 * @param mutex Pointer to mutex
 * @return 0 on success, error code on failure
 */
int pthread_mutex_lock(pthread_mutex_t *mutex);

/**
 * @brief Try to lock a mutex (non-blocking)
 * @param mutex Pointer to mutex
 * @return 0 on success, EBUSY if already locked
 */
int pthread_mutex_trylock(pthread_mutex_t *mutex);

/**
 * @brief Unlock a mutex
 * @param mutex Pointer to mutex
 * @return 0 on success, error code on failure
 */
int pthread_mutex_unlock(pthread_mutex_t *mutex);

/**
 * @brief Destroy a mutex
 * @param mutex Pointer to mutex
 * @return 0 on success, error code on failure
 */
int pthread_mutex_destroy(pthread_mutex_t *mutex);

/* =========================================================================
 * Semaphore API
 * ========================================================================= */

/**
 * @brief Initialize a semaphore
 * @param sem Pointer to semaphore
 * @param pshared Sharing mode (0 = thread-private)
 * @param value Initial value
 * @return 0 on success, -1 on failure
 */
int sem_init(sem_t *sem, int pshared, unsigned int value);

/**
 * @brief Wait (decrement) on a semaphore (blocking)
 * @param sem Pointer to semaphore
 * @return 0 on success, -1 on failure
 */
int sem_wait(sem_t *sem);

/**
 * @brief Try to wait (decrement) on a semaphore (non-blocking)
 * @param sem Pointer to semaphore
 * @return 0 on success, -1 on failure (EAGAIN if would block)
 */
int sem_trywait(sem_t *sem);

/**
 * @brief Post (increment) a semaphore
 * @param sem Pointer to semaphore
 * @return 0 on success, -1 on failure
 */
int sem_post(sem_t *sem);

/**
 * @brief Get the value of a semaphore
 * @param sem Pointer to semaphore
 * @param sval Pointer to store value
 * @return 0 on success, -1 on failure
 */
int sem_getvalue(sem_t *sem, int *sval);

/**
 * @brief Destroy a semaphore
 * @param sem Pointer to semaphore
 * @return 0 on success, -1 on failure
 */
int sem_destroy(sem_t *sem);

/* =========================================================================
 * Message Queue API
 * ========================================================================= */

/**
 * @brief Open a message queue
 * @param name Queue name
 * @param oflag Open flags
 * @return Message queue descriptor, or -1 on failure
 */
mqd_t mq_open(const char *name, int oflag);

/**
 * @brief Send a message to a queue
 * @param mqdes Message queue descriptor
 * @param msg_ptr Pointer to message data
 * @param msg_len Message length
 * @param msg_prio Message priority
 * @return 0 on success, -1 on failure
 */
int mq_send(mqd_t mqdes, const char *msg_ptr, size_t msg_len,
            unsigned int msg_prio);

/**
 * @brief Receive a message from a queue
 * @param mqdes Message queue descriptor
 * @param msg_ptr Buffer to store received message
 * @param msg_len Buffer size
 * @param msg_prio Pointer to store message priority (may be NULL)
 * @return Number of bytes received, or -1 on failure
 */
int mq_receive(mqd_t mqdes, char *msg_ptr, size_t msg_len,
               unsigned int *msg_prio);

/**
 * @brief Close a message queue
 * @param mqdes Message queue descriptor
 * @return 0 on success, -1 on failure
 */
int mq_close(mqd_t mqdes);

/* =========================================================================
 * File I/O API
 * ========================================================================= */

/**
 * @brief Open a file/device
 * @param fd_type File descriptor type (FD_TYPE_UART, FD_TYPE_GPIO, etc.)
 * @param flags Open flags
 * @return File descriptor on success, -1 on failure
 */
int open(int fd_type, int flags);

/**
 * @brief Close a file descriptor
 * @param fd File descriptor
 * @return 0 on success, -1 on failure
 */
int close(int fd);

/**
 * @brief Read from a file descriptor
 * @param fd File descriptor
 * @param buf Buffer to read into
 * @param count Maximum number of bytes to read
 * @return Number of bytes read, or -1 on failure
 */
int read(int fd, void *buf, size_t count);

/**
 * @brief Write to a file descriptor
 * @param fd File descriptor
 * @param buf Data to write
 * @param count Number of bytes to write
 * @return Number of bytes written, or -1 on failure
 */
int write(int fd, const void *buf, size_t count);

/**
 * @brief Device I/O control
 * @param fd File descriptor
 * @param request ioctl request code
 * @param arg Argument
 * @return 0 on success, -1 on failure
 */
int ioctl(int fd, unsigned long request, unsigned long arg);

/**
 * @brief Reposition file offset
 * @param fd File descriptor
 * @param offset Offset value
 * @param whence SEEK_SET, SEEK_CUR, or SEEK_END
 * @return New offset on success, -1 on failure
 */
int lseek(int fd, long offset, int whence);

/* =========================================================================
 * Timer / Clock API
 * ========================================================================= */

/**
 * @brief Get current time
 * @param clk_id Clock ID (CLOCK_REALTIME or CLOCK_MONOTONIC)
 * @param tp Pointer to timespec structure
 * @return 0 on success, -1 on failure
 */
int clock_gettime(clockid_t clk_id, timespec_t *tp);

/**
 * @brief Sleep for a specified duration
 * @param req Requested sleep duration
 * @param rem Remaining time if interrupted (may be NULL)
 * @return 0 on success, -1 on failure
 */
int nanosleep(const timespec_t *req, timespec_t *rem);

#endif /* VSYNC_POSIX_H */
