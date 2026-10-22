# Raw-clones the Pi SSD (disk 3) onto a blank drive (disk 2). Must run elevated.
# -ResumeGB N : continue from N GB (target must already hold the first N GB; skips the wipe).
# Unreadable source sectors are zero-filled and listed in the log.
param([int]$ResumeGB = 0)
$ErrorActionPreference = 'Stop'
$log = 'C:\Users\singh\claude_work\pi-restore-tools\clone.log'
function Log($m){ $l = "$(Get-Date -f 'HH:mm:ss') $m"; Write-Host $l; $l | Out-File -FilePath $log -Append -Encoding ascii }
function Finish($code){ Write-Host ''; Read-Host 'Press Enter to close' | Out-Null; exit $code }
if($ResumeGB -eq 0){ '' | Out-File $log -Encoding ascii }
trap { Log "ERROR: $($_ | Out-String)"; Finish 1 }
$srcN=3; $dstN=2
$src = Get-Disk $srcN; $dst = Get-Disk $dstN
# Safety guards: refuse to run if the disks aren't exactly the ones inspected
if($src.Size -ne 120034123776 -or $dst.Size -ne 128035676160 -or $dst.BusType -ne 'USB' -or $src.BusType -ne 'USB'){ Log 'ABORT: disk identity mismatch'; Finish 1 }
if((Get-Partition -DiskNumber $dstN -ErrorAction SilentlyContinue | Where-Object DriveLetter -ne $null | ForEach-Object { (Get-ChildItem "$($_.DriveLetter):\" -Force -ErrorAction SilentlyContinue | Where-Object Name -ne 'System Volume Information').Count } | Measure-Object -Sum).Sum -gt 0){ Log 'ABORT: target has files'; Finish 1 }
Log 'Preparing target'
if($ResumeGB -eq 0 -and (Get-Disk $dstN).PartitionStyle -ne 'RAW'){ Clear-Disk -Number $dstN -RemoveData -RemoveOEM -Confirm:$false }
if(-not (Get-Disk $dstN).IsOffline){ Set-Disk -Number $dstN -IsOffline $true }
Log 'Opening disks'
$in  = New-Object IO.FileStream("\\.\PhysicalDrive$srcN",'Open','Read','ReadWrite',4MB)
$out = New-Object IO.FileStream("\\.\PhysicalDrive$dstN",'Open','Write','ReadWrite',4MB)
$buf = New-Object byte[] (4MB); $total=[long]$src.Size
$done=[long]$ResumeGB*1GB; $last=$done; $bad=0
$in.Seek($done,'Begin') | Out-Null; $out.Seek($done,'Begin') | Out-Null
try{
  while($done -lt $total){
    $want=[int]([Math]::Min([long]$buf.Length,[long]($total-$done)))
    try { $n=$in.Read($buf,0,$want); if($n -le 0){ throw 'eof' } }
    catch {
      # Retry this chunk in 4 KB pieces; zero-fill what can't be read
      $n=0
      while($n -lt $want){
        $p=[int][Math]::Min(4096,$want-$n)
        try { $in.Seek($done+$n,'Begin') | Out-Null; $r=$in.Read($buf,$n,$p); if($r -le 0){ throw 'eof' } }
        catch { [Array]::Clear($buf,$n,$p); $r=$p; $bad++; Log ("UNREADABLE offset {0}" -f ($done+$n)) }
        $n+=$r
      }
      $in.Seek($done+$n,'Begin') | Out-Null
    }
    $out.Write($buf,0,[int]([Math]::Ceiling($n/512.0)*512)); $done+=$n
    if($done-$last -ge 1GB){ Log ("{0:N1} / {1:N1} GB" -f ($done/1GB),($total/1GB)); $last=$done }
  }
  $out.Flush()
} finally { $in.Close(); $out.Close() }
Log "COPY DONE (unreadable 4KB blocks zero-filled: $bad)"
Set-Disk -Number $dstN -IsOffline $false -ErrorAction SilentlyContinue
Log 'FINISHED'
Finish 0
