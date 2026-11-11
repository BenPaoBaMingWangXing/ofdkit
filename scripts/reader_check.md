# 用 ofdrw 验证生成结果

`ofdkit verify` 与 `scripts/verify_ofd.py` 都是本项目自己写的检查。它们能证明包结构自洽，但证明不了"另一个实现能读"。

这一步用 [ofdrw](https://github.com/ofdrw/ofdrw)（Java 的 OFD 阅读器，MIT，1.9k stars）真正打开生成的包，逐页遍历图层与对象。ofdrw 解析不了的东西，真实阅读器大概率也解析不了。

## 准备

需要一个 JRE/JDK 17 和 ofdrw 的 jar。jar 体积加起来约 11 MB，不进仓库，按需下载。

```bash
mkdir -p /tmp/ofdcheck/lib && cd /tmp/ofdcheck

# JDK 17（华为云镜像，约 178 MB，20 秒左右）
curl -L -o jdk.zip https://mirrors.huaweicloud.com/openjdk/17.0.2/openjdk-17.0.2_windows-x64_bin.zip
unzip -q jdk.zip

# ofdrw 2.5.1 与它的依赖，来自 Maven Central
M=https://repo1.maven.org/maven2
for p in \
  org/ofdrw/ofdrw-core/2.5.1/ofdrw-core-2.5.1.jar \
  org/ofdrw/ofdrw-reader/2.5.1/ofdrw-reader-2.5.1.jar \
  org/ofdrw/ofdrw-pkg/2.5.1/ofdrw-pkg-2.5.1.jar \
  org/ofdrw/ofdrw-gv/2.5.1/ofdrw-gv-2.5.1.jar \
  org/ofdrw/ofdrw-gm/2.5.1/ofdrw-gm-2.5.1.jar \
  org/apache/commons/commons-compress/1.28.0/commons-compress-1.28.0.jar \
  commons-io/commons-io/2.18.0/commons-io-2.18.0.jar \
  org/dom4j/dom4j/2.1.4/dom4j-2.1.4.jar \
  jaxen/jaxen/1.2.0/jaxen-1.2.0.jar \
  org/bouncycastle/bcprov-jdk18on/1.78.1/bcprov-jdk18on-1.78.1.jar \
  net/lingala/zip4j/zip4j/2.11.3/zip4j-2.11.3.jar \
  org/slf4j/slf4j-api/2.0.16/slf4j-api-2.0.16.jar \
  org/slf4j/slf4j-simple/2.0.16/slf4j-simple-2.0.16.jar ; do
  curl -sL -O "$M/$p" -o "lib/$(basename $p)" --create-dirs
done
```

## 编译并运行

```bash
JAVA_HOME=/tmp/ofdcheck/jdk-17.0.2
CP="$(ls /tmp/ofdcheck/lib/*.jar | tr '\n' ';')"

"$JAVA_HOME/bin/javac" -encoding UTF-8 -cp "$CP" -d /tmp/ofdcheck/classes scripts/java/ReadOfd.java
"$JAVA_HOME/bin/java" -Dfile.encoding=UTF-8 \
  -Dorg.slf4j.simpleLogger.defaultLogLevel=error \
  -cp "$CP;/tmp/ofdcheck/classes" ReadOfd out/demo.ofd
```

## 2026-11-11 的实测结果

用 `moon run cmd/main -- demo out/final.ofd <simhei> <seal.png>` 生成的包：

```
pages=2
page 1 size=0 0 210 297
page 2 size=0 0 210 297
textObjects=16
textCodes=16
pathObjects=14
imageObjects=1
otherObjects=0
sampleText=ofdkitOFD 文档生成器纯 MoonBit 实现 · 符合 GB/T 33190-2016
```

ofdrw 2.5.1 / OpenJDK 17.0.2，无异常、无警告。

这说明：

- ZIP 容器与目录记录可被 zlib/zip4j 之外的另一套实现解析
- `OFD.xml` → `Document.xml` → 每页 `Content.xml` 的引用链能走通
- 页面尺寸被正确识别为 A4（210×297 mm）
- 文本对象、路径对象、图片对象都被识别成对应类型，而不是落进 `otherObjects`
- 中文文本经 UTF-8 解码后内容正确

## 这份验证证明不了什么

- **不证明渲染正确**。ofdrw 读出对象树，不等于它把这些对象画在正确的位置。要验证渲染，得用 ofdrw-converter 或真实阅读器截图对比。
- **不覆盖所有阅读器**。不同阅读器对可选元素的容忍度不同。ofdrw 能读是一个强信号，不是万能证明。
- **不覆盖签章**。本项目没有实现签名，ofdrw 的签名校验路径没有被触发。
