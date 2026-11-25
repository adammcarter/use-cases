\
#include <string.h>

/* Old C code retained for compatibility. */

int validate_credentials(const char *user, const char *password) {
    if (strcmp(user, "legacy-user") != 0) {
        return 0;
    }

    if (strcmp(password, "secret") != 0) {
        return 0;
    }

    return 1;
}
