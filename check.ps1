# rftools 全站静态校验
# 用法: powershell -ExecutionPolicy Bypass -File check.ps1
# 检查:目录结构(4 目录 x 7 页 + index)、零死链、每页必需元素、旧文件名无残留引用

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $root

$fail = 0
function Fail($msg) { Write-Host "[FAIL] $msg" -ForegroundColor Red; $script:fail++ }
function Ok($msg)   { Write-Host "[ OK ] $msg" -ForegroundColor Green }

# ---------- 1. 目录结构 ----------
$dirs = @('RF', 'DSP', 'FMCW', 'SDR')
$expected = @{
    'RF'   = @('01-dB单位与链路预算.html','02-传输线反射与VSWR.html','03-史密斯圆图与匹配.html','04-滤波器频响.html','05-噪声系数与灵敏度.html','06-非线性与动态范围.html','07-PLL与相位噪声.html')
    'DSP'  = @('01-傅里叶级数与频谱.html','02-采样量化与混叠.html','03-FFT频谱分析.html','04-窗函数与泄漏.html','05-复信号与IQ.html','06-随机信号与噪声.html','07-卷积与LTI系统.html')
    'FMCW' = @('01-雷达原理与雷达方程.html','02-FMCW测距原理.html','03-多普勒测速与RD图.html','04-chirp参数设计.html','05-CFAR恒虚警检测.html','06-阵列测角与MIMO.html','07-雷达处理全流水线.html')
    'SDR'  = @('01-SDR概念与架构.html','02-采样策略与带通采样.html','03-DDC与抽取.html','04-模拟调制AM与FM.html','05-数字调制与星座图.html','06-信道损伤与误码率.html','07-频谱仪与瀑布图.html')
}
if (Test-Path "$root\index.html") { Ok "index.html 存在" } else { Fail "缺少 index.html" }

foreach ($d in $dirs) {
    foreach ($f in $expected[$d]) {
        $p = Join-Path $root "$d\$f"
        if (Test-Path -LiteralPath $p) { } else { Fail "缺少 $d/$f" }
    }
    $actual = @(Get-ChildItem -LiteralPath (Join-Path $root $d) -Filter *.html -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '^~~' })
    if ($actual.Count -ne 7) { Fail "${d} 目录应有 7 个 html,实际 $($actual.Count) 个:$($actual.Name -join ', ')" }
}

# 旧综合页必须已删除
$oldFiles = @('RF\射频基础.html','DSP\信号处理基础.html','FMCW\毫米波雷达基础.html','SDR\SDR基础.html')
foreach ($o in $oldFiles) {
    if (Test-Path -LiteralPath (Join-Path $root $o)) { Fail "旧综合页仍存在: $o(应已 git rm)" }
}
if (Test-Path "$root\SP") { Fail "空目录 SP/ 仍存在" }

# ---------- 2. 逐页检查 + 死链扫描 ----------
$allHtml = @(Get-ChildItem -LiteralPath $root -Recurse -Filter *.html)
$linkRe  = [regex]'(?:href|src)\s*=\s*["'']([^"''#?]+)(?:[#?][^"'']*)?["'']'
$siteLinks = 0

foreach ($file in $allHtml) {
    $rel = $file.FullName.Substring($root.Length + 1)
    $text = [IO.File]::ReadAllText($file.FullName)   # UTF-8 无 BOM 兼容

    if ($text -notmatch '</html>')            { Fail "$rel : 文件不完整(缺 </html>)"; continue }
    if ($file.Name -ne 'index.html') {
        if ($text -notmatch 'class="sim"')    { Fail "$rel : 缺少仿真区 class=sim" }
        if ($text -notmatch '<canvas')        { Fail "$rel : 缺少 canvas" }
        if ($text -notmatch '\.back')         { Fail "$rel : 缺少返回首页链接" }
    }

    foreach ($m in $linkRe.Matches($text)) {
        $href = $m.Groups[1].Value
        if ($href -match '^(https?:|mailto:|javascript:|data:)') { continue }   # 外部/协议链接跳过
        if ($href -eq '' ) { continue }
        $baseDir = $file.DirectoryName
        $target = [IO.Path]::GetFullPath((Join-Path $baseDir $href))
        if (-not (Test-Path -LiteralPath $target)) { Fail "$rel : 死链 -> $href" }
        if ($file.Name -eq 'index.html') { $siteLinks++ }
    }
}

# ---------- 3. index 链接数(28 专题页 + 总览页) ----------
if ($siteLinks -eq 29) { Ok "index.html 站内链接 29 个" } else { Fail "index.html 站内链接应为 29,实际 $siteLinks" }

# ---------- 4. 旧文件名残留引用 ----------
foreach ($file in $allHtml) {
    $rel = $file.FullName.Substring($root.Length + 1)
    $text = [IO.File]::ReadAllText($file.FullName)
    foreach ($o in @('射频基础.html','信号处理基础.html','毫米波雷达基础.html','SDR基础.html')) {
        if ($text.Contains($o)) { Fail "$rel : 仍引用旧文件名 $o" }
    }
}

# ---------- 汇总 ----------
if ($fail -eq 0) {
    Write-Host "`n全部通过:$($allHtml.Count) 个 html,结构 4x7+index,零死链,旧页无残留" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n共 $fail 项失败" -ForegroundColor Red
    exit 1
}
