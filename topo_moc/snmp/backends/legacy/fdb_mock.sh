#!/bin/sh

# 定义 MAC 对应的十进制 OID 后缀
SUFFIX_1="0.17.34.51.68.1"
PORT_1="5"
MAC_HEX_1="00 11 22 33 44 01"

SUFFIX_2="0.17.34.51.68.2"
PORT_2="5"
MAC_HEX_2="00 11 22 33 44 02"

SUFFIX_3="0.17.34.51.68.3"
PORT_3="6"
MAC_HEX_3="00 11 22 33 44 03"

# 统一使用无前导点的 OID 基准
ENTRY_BASE="1.3.6.1.2.1.17.4.3.1"
ADDR_BASE="1.3.6.1.2.1.17.4.3.1.1"
PORT_BASE="1.3.6.1.2.1.17.4.3.1.2"

REQ_TYPE="$1"
# 预处理：剥离 REQ_OID 最前面的 '.'，确保格式一致
REQ_OID=$(echo "$2" | sed 's/^\.//')

if [ "$REQ_TYPE" = "-g" ]; then
    case "$REQ_OID" in
        "$ADDR_BASE.$SUFFIX_1")
            echo ".$ADDR_BASE.$SUFFIX_1"; echo "string"; echo "$MAC_HEX_1" ;;
        "$ADDR_BASE.$SUFFIX_2")
            echo ".$ADDR_BASE.$SUFFIX_2"; echo "string"; echo "$MAC_HEX_2" ;;
        "$ADDR_BASE.$SUFFIX_3")
            echo ".$ADDR_BASE.$SUFFIX_3"; echo "string"; echo "$MAC_HEX_3" ;;

        "$PORT_BASE.$SUFFIX_1")
            echo ".$PORT_BASE.$SUFFIX_1"; echo "integer"; echo "$PORT_1" ;;
        "$PORT_BASE.$SUFFIX_2")
            echo ".$PORT_BASE.$SUFFIX_2"; echo "integer"; echo "$PORT_2" ;;
        "$PORT_BASE.$SUFFIX_3")
            echo ".$PORT_BASE.$SUFFIX_3"; echo "integer"; echo "$PORT_3" ;;
        *)
            exit 0 ;;
    esac

elif [ "$REQ_TYPE" = "-n" ]; then
    case "$REQ_OID" in
        # 匹配入口点（兼容带 .0 情况）
        "$ENTRY_BASE"|"$ADDR_BASE"|"$ADDR_BASE.0")
            echo ".$ADDR_BASE.$SUFFIX_1"; echo "string"; echo "$MAC_HEX_1" ;;
        "$ADDR_BASE.$SUFFIX_1")
            echo ".$ADDR_BASE.$SUFFIX_2"; echo "string"; echo "$MAC_HEX_2" ;;
        "$ADDR_BASE.$SUFFIX_2")
            echo ".$ADDR_BASE.$SUFFIX_3"; echo "string"; echo "$MAC_HEX_3" ;;

        # Address 表末尾跨节点到 Port 表开头
        "$ADDR_BASE.$SUFFIX_3")
            echo ".$PORT_BASE.$SUFFIX_1"; echo "integer"; echo "$PORT_1" ;;

        # Port 表迭代
        "$PORT_BASE"|"$PORT_BASE.0")
            echo ".$PORT_BASE.$SUFFIX_1"; echo "integer"; echo "$PORT_1" ;;
        "$PORT_BASE.$SUFFIX_1")
            echo ".$PORT_BASE.$SUFFIX_2"; echo "integer"; echo "$PORT_2" ;;
        "$PORT_BASE.$SUFFIX_2")
            echo ".$PORT_BASE.$SUFFIX_3"; echo "integer"; echo "$PORT_3" ;;
        *)
            exit 0 ;;
    esac
fi
