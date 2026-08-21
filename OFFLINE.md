# Air-gapped transfer (no internet on the cluster)

The cluster (login container + compute nodes like `computing5`) has **no internet**,
so `git clone` will not work there. Move the repo as a file instead. It is small:
**~2.6 MB zipped**.

## 1. On the Windows machine (has internet)

Download the repository ZIP — one click:

**https://github.com/rainbay001-dotcom/coralnpu-fx600/archive/refs/heads/main.zip**

Copy `coralnpu-fx600-main.zip` into the folder you share with the VNC machine.

## 2. On the VNC Linux machine (the login node)

```bash
# find where the Windows share is mounted (one of these usually)
ls ~/shared ~/share /mnt/share /mnt/hgfs /media/sf_* 2>/dev/null
SHARE=<the path you found>

cd ~ && unzip -o "$SHARE/coralnpu-fx600-main.zip"
mv -f coralnpu-fx600-main coralnpu-fx600      # ZIP unpacks with a -main suffix
cd coralnpu-fx600
chmod +x donau/*.sh host/*.sh                 # ZIP loses the executable bit!
ls                                            # board build donau elf host rtl ...
```

## 3. Check that $HOME reaches the compute nodes

```bash
echo hello-from-login > ~/coralnpu-fx600/PING.txt
```
then, in an xterm on a compute node (`dsub -q normal --x11 xterm`):
```bash
cat ~/coralnpu-fx600/PING.txt      # should print hello-from-login
```
* **It prints** → home is shared (normal for HPC). Everything below just works.
* **It does not** → copy the ZIP to a filesystem the nodes do see (ask the admin
  which path is shared, e.g. `/work/$USER` or `/data/$USER`) and unpack there.

## 4. Sending results back to GitHub

Logs are text; the easy route is through the same share:

```bash
mkdir -p "$SHARE/coralnpu-out"
cp check.log build_scalar.log run.log "$SHARE/coralnpu-out/" 2>/dev/null
cp build/out_scalar/reports/*.rpt "$SHARE/coralnpu-out/" 2>/dev/null
```
Then open them in Notepad on Windows and paste into the GitHub issue.
(VNC clipboard copy from the xterm often works too — try selecting text with the
mouse and pasting into the browser.)

## 5. Getting an updated version later

Every fix lands in the repo; just download the ZIP again on Windows, unzip over
the top (`unzip -o`), and re-`chmod +x`. Your build outputs under
`build/out_*/` are untouched by that.

## Note: nothing in the flow needs the internet
The JTAG path uses only Vivado and its local IP catalog. (The PCIe/XDMA path
would need to fetch a driver from GitHub — that is why we are on JTAG.)
