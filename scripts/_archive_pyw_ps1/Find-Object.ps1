<#
.SYNOPSIS
    Поиск объектов в каталоге AIS (rules/object_catalog.jsonl).
.DESCRIPTION
    Загружает JSONL-каталог и ищет объекты по заданным критериям.
    Поддерживает фильтры: имя, тип, kind (PB/SQL), источник (current/main), библиотека.
    Показывает зависимости и обратные ссылки.
.PARAMETER Name
    Часть имени объекта (регулярное выражение).
.PARAMETER Kind
    'PB' или 'SQL'.
.PARAMETER ObjType
    Тип объекта (Procedure, Table, Window, DataWindow, UserObject и т.д.).
.PARAMETER Src
    'current' или 'main'.
.PARAMETER Lib
    Библиотека/папка.
.PARAMETER ShowDeps
    Показать зависимости (tables, calls, sqlRefs, pbRefs).
.PARAMETER Reverse
    Найти объекты, которые ссылаются на заданный (обратный поиск).
.PARAMETER CatalogPath
    Путь к каталогу (по умолчанию rules/object_catalog.jsonl).
.PARAMETER Format
    'table' | 'json' | 'list' (по умолчанию table).
#>
param(
    [string]$Name,
    [ValidateSet('PB','SQL')][string]$Kind,
    [string]$ObjType,
    [ValidateSet('current','main')][string]$Src,
    [string]$Lib,
    [switch]$ShowDeps,
    [switch]$Reverse,
    [string]$CatalogPath,
    [ValidateSet('table','json','list')][string]$Format = 'table'
)

$ErrorActionPreference = "Stop"

if (-not $CatalogPath) { $CatalogPath = "C:\AIS\AI\Prod\rules\object_catalog.jsonl" }
if (-not (Test-Path $CatalogPath)) { throw "Каталог не найден: $CatalogPath" }

Write-Host "Загрузка каталога: $CatalogPath" -ForegroundColor Cyan
$lines = Get-Content $CatalogPath -Raw -Encoding UTF8 -ErrorAction Stop
$objects = $lines -split "`r?`n" | Where-Object { $_ -match '\S' } | ForEach-Object { $_ | ConvertFrom-Json }
Write-Host ("Загружено объектов: " + $objects.Count) -ForegroundColor Cyan

# Построение обратного индекса (для Reverse)
$reverseIndex = @{}
foreach ($o in $objects) {
    $id = "$($o.kind)|$($o.src)|$($o.name)"
    if ($o.tables) {
        foreach ($t in $o.tables) {
            if (-not $reverseIndex.ContainsKey($t)) { $reverseIndex[$t] = @() }
            $reverseIndex[$t] += $id
        }
    }
    if ($o.calls) {
        foreach ($c in $o.calls) {
            if (-not $reverseIndex.ContainsKey($c)) { $reverseIndex[$c] = @() }
            $reverseIndex[$c] += $id
        }
    }
    if ($o.sqlRefs) {
        foreach ($s in $o.sqlRefs) {
            if (-not $reverseIndex.ContainsKey($s)) { $reverseIndex[$s] = @() }
            $reverseIndex[$s] += $id
        }
    }
    if ($o.pbRefs) {
        foreach ($p in $o.pbRefs) {
            if (-not $reverseIndex.ContainsKey($p)) { $reverseIndex[$p] = @() }
            $reverseIndex[$p] += $id
        }
    }
}

# Фильтрация
$filtered = $objects
if ($Kind) { $filtered = $filtered | Where-Object { $_.kind -eq $Kind } }
if ($Src)  { $filtered = $filtered | Where-Object { $_.src  -eq $Src } }
if ($ObjType) { $filtered = $filtered | Where-Object { $_.objType -like "*$ObjType*" } }
if ($Lib)  { $filtered = $filtered | Where-Object { $_.lib -like "*$Lib*" } }
if ($Name) { $filtered = $filtered | Where-Object { $_.name -match $Name } }

if ($Reverse) {
    $targetNames = @($filtered | ForEach-Object { $_.name })
    $referrers = @{}
    foreach ($tn in $targetNames) {
        if ($reverseIndex.ContainsKey($tn.ToLower())) {
            foreach ($refId in $reverseIndex[$tn.ToLower()]) { $referrers[$refId] = $true }
        }
    }
    $filtered = $objects | Where-Object { $referrers.ContainsKey("$($_.kind)|$($_.src)|$($_.name)") }
    Write-Host ("Найдено ссылающихся объектов: " + $filtered.Count) -ForegroundColor Yellow
}

if (-not $filtered) { Write-Host "Ничего не найдено."; exit 0 }

# Вывод
if ($Format -eq 'json') {
    $filtered | ConvertTo-Json -Depth 4
} elseif ($Format -eq 'list') {
    $filtered | ForEach-Object { "$($_.kind) [$($_.src)] $($_.name) ($($_.objType))  lib=$($_.lib)" }
} else {
    $filtered | Select-Object @{n='Kind';e={$_.kind}}, @{n='Src';e={$_.src}}, @{n='Name';e={$_.name}}, @{n='Type';e={$_.objType}}, @{n='Lib';e={$_.lib}} | Format-Table -AutoSize
}

# Зависимости
if ($ShowDeps) {
    foreach ($o in $filtered) {
        Write-Host ("`n=== $($o.kind) [$($o.src)] $($o.name) ($($o.objType)) lib=$($o.lib) ===") -ForegroundColor Cyan
        if ($o.tables) { Write-Host ("  Tables: " + ($o.tables -join ', ')) -ForegroundColor Green }
        if ($o.calls)  { Write-Host ("  Calls : " + ($o.calls  -join ', ')) -ForegroundColor Green }
        if ($o.sqlRefs) { Write-Host ("  SQL Refs: " + ($o.sqlRefs -join ', ')) -ForegroundColor Yellow }
        if ($o.pbRefs) { Write-Host ("  PB Refs : " + ($o.pbRefs -join ', ')) -ForegroundColor Yellow }
    }
}