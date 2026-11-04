#ifndef HPTNACP_SETTINGS_H
#define HPTNACP_SETTINGS_H

#if defined(_WIN32) || defined(_WIN64)
#define USAGE_PROGRAM_NAME "hptnacp.exe"
#define OS_PATH_SEPARATOR "\\"
#else
#define USAGE_PROGRAM_NAME "hptnacp"
#define OS_PATH_SEPARATOR "/"
#endif

#define HPTNACP_VERSION "v1.03"

#endif