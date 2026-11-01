# Minimal read-only VPK v2 reader for browsing Deadlock game files.
# Usage:
#   .\vpk.ps1 list    -Vpk <path\pak01_dir.vpk> [-Filter <regex>]
#   .\vpk.ps1 extract -Vpk <path\pak01_dir.vpk> -Filter <regex> -Out <dir> [-Panorama]
# -Panorama additionally decodes compiled panorama files (.vxml_c/.vjs_c/.vcss_c/.vts_c)
# into plain source next to the raw file.
param(
    [Parameter(Position = 0, Mandatory)] [ValidateSet('list', 'extract')] [string]$Command,
    [Parameter(Mandatory)] [string]$Vpk,
    [string]$Filter = '.',
    [string]$Out = '.\extracted',
    [switch]$Panorama
)

$ErrorActionPreference = 'Stop'

if (-not ('VpkReader' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Text;

public class VpkEntry {
    public string Path;
    public uint Crc;
    public byte[] Preload;
    public ushort ArchiveIndex;
    public uint Offset;
    public uint Length;
}

public class VpkReader {
    public string DirPath;
    public uint TreeSize;
    public uint HeaderSize;
    public List<VpkEntry> Entries = new List<VpkEntry>();

    static string ReadZ(BinaryReader r) {
        var sb = new List<byte>();
        byte b;
        while ((b = r.ReadByte()) != 0) sb.Add(b);
        return Encoding.UTF8.GetString(sb.ToArray());
    }

    public VpkReader(string dirPath) {
        DirPath = dirPath;
        using (var r = new BinaryReader(File.OpenRead(dirPath))) {
            if (r.ReadUInt32() != 0x55aa1234) throw new Exception("Not a VPK");
            uint version = r.ReadUInt32();
            TreeSize = r.ReadUInt32();
            if (version == 1) HeaderSize = 12;
            else if (version == 2) { r.ReadBytes(16); HeaderSize = 28; }
            else throw new Exception("Unsupported VPK version " + version);

            while (true) {
                string ext = ReadZ(r);
                if (ext.Length == 0) break;
                while (true) {
                    string dir = ReadZ(r);
                    if (dir.Length == 0) break;
                    while (true) {
                        string name = ReadZ(r);
                        if (name.Length == 0) break;
                        var e = new VpkEntry();
                        e.Crc = r.ReadUInt32();
                        ushort preload = r.ReadUInt16();
                        e.ArchiveIndex = r.ReadUInt16();
                        e.Offset = r.ReadUInt32();
                        e.Length = r.ReadUInt32();
                        r.ReadUInt16(); // 0xffff terminator
                        e.Preload = r.ReadBytes(preload);
                        string d = dir.Trim() == "" ? "" : dir + "/";
                        e.Path = d + name + "." + ext;
                        Entries.Add(e);
                    }
                }
            }
        }
    }

    public byte[] Read(VpkEntry e) {
        var ms = new MemoryStream();
        ms.Write(e.Preload, 0, e.Preload.Length);
        if (e.Length > 0) {
            string file; long off;
            if (e.ArchiveIndex == 0x7fff) {
                file = DirPath; off = HeaderSize + TreeSize + e.Offset;
            } else {
                file = DirPath.Replace("_dir.vpk", "_" + e.ArchiveIndex.ToString("D3") + ".vpk");
                off = e.Offset;
            }
            using (var fs = File.OpenRead(file)) {
                fs.Seek(off, SeekOrigin.Begin);
                var buf = new byte[e.Length];
                int read = 0;
                while (read < buf.Length) read += fs.Read(buf, read, buf.Length - read);
                ms.Write(buf, 0, buf.Length);
            }
        }
        return ms.ToArray();
    }

    // Returns the DATA block of a compiled Source 2 resource, or null.
    public static byte[] DataBlock(byte[] res) {
        using (var r = new BinaryReader(new MemoryStream(res))) {
            r.ReadUInt32(); r.ReadUInt16(); r.ReadUInt16();
            long blockOffsetPos = r.BaseStream.Position;
            uint blockOffset = r.ReadUInt32();
            uint blockCount = r.ReadUInt32();
            r.BaseStream.Seek(blockOffsetPos + blockOffset, SeekOrigin.Begin);
            for (int i = 0; i < blockCount; i++) {
                string type = Encoding.ASCII.GetString(r.ReadBytes(4));
                long pos = r.BaseStream.Position;
                uint off = r.ReadUInt32();
                uint size = r.ReadUInt32();
                if (type == "DATA") {
                    var outb = new byte[size];
                    Array.Copy(res, pos + off, outb, 0, size);
                    return outb;
                }
            }
        }
        return null;
    }
}
'@
}

$reader = [VpkReader]::new((Resolve-Path $Vpk).Path)
$matched = $reader.Entries | Where-Object { $_.Path -match $Filter }

if ($Command -eq 'list') {
    $matched | ForEach-Object { '{0,10}  {1}' -f $_.Length, $_.Path }
    return
}

foreach ($e in $matched) {
    $dest = Join-Path $Out $e.Path
    New-Item -ItemType Directory -Force (Split-Path $dest) | Out-Null
    $bytes = $reader.Read($e)
    [IO.File]::WriteAllBytes($dest, $bytes)
    if ($Panorama -and $e.Path -match '\.v(xml|js|css|ts)_c$') {
        $data = [VpkReader]::DataBlock($bytes)
        if ($data) {
            # Panorama DATA block: crc32, uint16 name-count + names, then source text.
            # Locate the source by skipping to the first plausible text start.
            $text = [Text.Encoding]::UTF8.GetString($data)
            $start = $text.IndexOfAny([char[]]'<"/@.'.ToCharArray(), 6)
            if ($start -lt 0) { $start = 0 }
            [IO.File]::WriteAllText(($dest -replace '_c$', ''), $text.Substring($start).TrimEnd([char]0))
        }
    }
    $e.Path
}
