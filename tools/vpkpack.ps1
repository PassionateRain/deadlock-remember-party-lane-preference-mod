# Packs a directory into a single-file VPK v2 (all data inside the _dir file, no numbered archives).
# Usage: .\tools\vpkpack.ps1 -Dir build\party_lane_probe -Out build\party_lane_probe.vpk
param(
    [Parameter(Mandatory)] [string]$Dir,
    [Parameter(Mandatory)] [string]$Out
)

$ErrorActionPreference = 'Stop'

if (-not ('VpkWriter' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;

public static class VpkWriter {
    static uint[] crcTable;
    static uint Crc32(byte[] data) {
        if (crcTable == null) {
            crcTable = new uint[256];
            for (uint i = 0; i < 256; i++) {
                uint c = i;
                for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320u ^ (c >> 1) : c >> 1;
                crcTable[i] = c;
            }
        }
        uint crc = 0xFFFFFFFFu;
        foreach (byte b in data) crc = crcTable[(crc ^ b) & 0xFF] ^ (crc >> 8);
        return crc ^ 0xFFFFFFFFu;
    }

    static void WriteZ(BinaryWriter w, string s) {
        w.Write(Encoding.UTF8.GetBytes(s));
        w.Write((byte)0);
    }

    public static void Pack(string dir, string outPath) {
        dir = Path.GetFullPath(dir).TrimEnd('\\', '/');
        var files = Directory.GetFiles(dir, "*", SearchOption.AllDirectories);

        // Group: extension -> directory -> files (VPK tree order).
        var groups = files
            .Select(f => {
                string rel = f.Substring(dir.Length + 1).Replace('\\', '/');
                string ext = Path.GetExtension(rel).TrimStart('.');
                string d = Path.GetDirectoryName(rel).Replace('\\', '/');
                string name = Path.GetFileNameWithoutExtension(rel);
                return new { Full = f, Ext = ext == "" ? " " : ext, Dir = d == "" ? " " : d, Name = name };
            })
            .GroupBy(x => x.Ext)
            .OrderBy(g => g.Key, StringComparer.Ordinal);

        var tree = new MemoryStream();
        var data = new MemoryStream();
        var tw = new BinaryWriter(tree);
        foreach (var eg in groups) {
            WriteZ(tw, eg.Key);
            foreach (var dg in eg.GroupBy(x => x.Dir).OrderBy(g => g.Key, StringComparer.Ordinal)) {
                WriteZ(tw, dg.Key);
                foreach (var f in dg.OrderBy(x => x.Name, StringComparer.Ordinal)) {
                    byte[] bytes = File.ReadAllBytes(f.Full);
                    WriteZ(tw, f.Name);
                    tw.Write(Crc32(bytes));
                    tw.Write((ushort)0);          // preload bytes
                    tw.Write((ushort)0x7fff);     // archive index: data lives in this file
                    tw.Write((uint)data.Length);  // offset within data section
                    tw.Write((uint)bytes.Length);
                    tw.Write((ushort)0xffff);     // terminator
                    data.Write(bytes, 0, bytes.Length);
                }
                tw.Write((byte)0);
            }
            tw.Write((byte)0);
        }
        tw.Write((byte)0);
        tw.Flush();

        byte[] treeBytes = tree.ToArray();
        byte[] dataBytes = data.ToArray();
        using (var md5 = MD5.Create()) {
            var head = new MemoryStream();
            var hw = new BinaryWriter(head);
            hw.Write(0x55aa1234u);
            hw.Write(2u);
            hw.Write((uint)treeBytes.Length);
            hw.Write((uint)dataBytes.Length);
            hw.Write(0u);   // archive MD5 section size
            hw.Write(48u);  // other MD5 section size
            hw.Write(0u);   // signature section size
            hw.Write(treeBytes);
            hw.Write(dataBytes);
            byte[] treeMd5 = md5.ComputeHash(treeBytes);
            byte[] archiveMd5 = md5.ComputeHash(new byte[0]);
            hw.Write(treeMd5);
            hw.Write(archiveMd5);
            hw.Flush();
            byte[] soFar = head.ToArray();
            byte[] wholeMd5 = md5.ComputeHash(soFar);
            using (var fs = File.Create(outPath)) {
                fs.Write(soFar, 0, soFar.Length);
                fs.Write(wholeMd5, 0, wholeMd5.Length);
            }
        }
    }
}
'@
}

[VpkWriter]::Pack((Resolve-Path $Dir).Path, [IO.Path]::GetFullPath($Out))
