// 強制インクルード: CSP本体がWindows/Qt環境で暗黙に取得していたヘッダを補う
#pragma once
#ifdef __cplusplus
#include <climits>
#include <cwchar>
#include <cctype>
#include <string>
#include <algorithm>
#include <cstdarg>
#include <cstring>
#endif
#ifdef __cplusplus
#include <sys/stat.h>
#include <sys/types.h>
#endif
#include <stdint.h>
#ifdef __cplusplus
typedef intptr_t LONG_PTR;
typedef uintptr_t ULONG_PTR;
#endif
