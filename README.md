<h1 align="center">PS5 Lua Autoloader Games Availability By RajabTechs</h1>
<h3 align="center">Fork of <a href="https://github.com/shahrilnet/remote_lua_loader">remote_lua_loader</a></h3>
&nbsp;
<p align="center">Automatically loads your .elf, .bin and .lua payloads.<br>Supports PS5 firmwares up to 12.70.</p>

<p align="center">
    <b>Other Autoloaders:</b><br>
    <a href="https://github.com/itsPLK/ps5-y2jb-autoloader">PS5 Y2JB Autoloader</a> | 
    <a href="https://github.com/itsPLK/ps5-bdjb-autoloader">PS5 BD-JB Autoloader</a>
</p>

---

## 🚀 How to use
* Create a directory named `ps5_autoloader`.
* Inside this directory, place your .elf/.bin/.lua files, and an `autoload.txt` file.
    * In autoload.txt, list the files you want to load (one per line).
    * Filenames are case-sensitive - make sure the names exactly match your files.
    * You can add lines like `!1000` to make the loader wait 1000ms before sending the next payload.
    * Note: Do not put kernel exploit or elfldr in `autoload.txt`, as they are loaded automatically.
* Put the `ps5_autoloader` directory in one of these locations:
    * In the root of a USB drive
    * In the internal drive at `/data/ps5_autoloader`
    * In the game’s savedata folder
* Import savedata to your game:  
  Follow the steps in [SETUP.md](SETUP.md) to prepare and import the savedata for your Lua-compatible game.

---

## 🎮 Game Compatibility & Availability

| Game Title                                   | TITLE ID   | Link                                                                                          | Price in USD | Available |
|----------------------------------------------|------------|-----------------------------------------------------------------------------------------------|-------       |-----------|
| Raspberry Cube                               | CUSA16074  | [Play-Asia](https://www.play-asia.com/en/search/Raspberry+Cube)                               | 63           | ✅ TRUE   |
| Aibeya                                       | CUSA17068  | [Play-Asia](https://www.play-asia.com/en/search/Aibeya)                                       | N/A          | ❌ FALSE  |
| Hamidashi Creative                           | CUSA27389  | [Play-Asia](https://www.play-asia.com/en/search/Hamidashi+Creative)                           | 63           | ✅ TRUE   |
| Hamidashi Creative Demo                      | CUSA27390  | [Play-Asia](https://www.play-asia.com/en/search/Hamidashi+Creative+Demo)                      | 63           | ✅ TRUE   |
| Aikagi Kimi to Issho ni Pack                 | CUSA16229  | [Play-Asia](https://www.play-asia.com/en/search/Aikagi+Kimi+to+Issho+ni+Pack)                 | N/A          | ❌ FALSE  |
| Aikagi 2                                     | CUSA19556  | [Play-Asia](https://www.play-asia.com/en/search/Aikagi+2)                                     | N/A          | ❌ FALSE  |
| IxSHE Tell                                   | CUSA17112  | [Play-Asia](https://www.play-asia.com/en/search/IxSHE+Tell)                                   | N/A          | ❌ FALSE  |
| Nora Princess and Stray Cat Heart HD         | CUSA13303  | [Play-Asia](https://www.play-asia.com/en/search/Nora+Princess+and+Stray+Cat+Heart+HD)         | N/A          | ❌ FALSE  |
| Jinki Resurrection                           | CUSA25179  | [Play-Asia](https://www.play-asia.com/en/search/Jinki+Resurrection)                           | N/A          | ❌ FALSE  |
| Fuyu Kiss                                    | CUSA29745  | [Play-Asia](https://www.play-asia.com/en/search/Fuyu+Kiss)                                    | N/A          | ❌ FALSE  |
| Nora Princess and Crying Cat 2               | CUSA13586  | [Play-Asia](https://www.play-asia.com/en/search/Nora+Princess+and+Crying+Cat+2)               | N/A          | ❌ FALSE  |
| Haruoto Alice Gram Snow Drop                 | CUSA14324  | [Play-Asia](https://www.play-asia.com/en/search/Haruoto+Alice+Gram+Snow+Drop)                 | N/A          | ❌ FALSE  |
| Tonari ni Kanojo no Iru Shiawase Winter Guest| CUSA11977  | [Play-Asia](https://www.play-asia.com/en/search/Tonari+ni+Kanojo+no+Iru+Shiawase+Winter+Guest)| N/A          | ❌ FALSE  |
| Mikagami Sumika no Seifuku Katsudou          | CUSA11481  | [Play-Asia](https://www.play-asia.com/en/search/Mikagami+Sumika+no+Seifuku+Katsudou)          | N/A          | ❌ FALSE  |
| Aerial Life                                  | CUSA17122  | [Play-Asia](https://www.play-asia.com/en/search/Aerial+Life)                                  | N/A          | ❌ FALSE  |

> **Note:** Demos require the latest firmware to download from PSN.

---

## 🔄 Updating Savedata
If you have the savedata setup and want to update the files, please refer to [UPDATE.md](UPDATE.md).

---

## ⚙️ Additional Info

<details>
<summary><i>How to use a custom ELF Loader version?</i></summary>

By default, the autoloader uses a custom version of **elfldr** that only accepts connections from the PS5 itself (localhost). This improves security by preventing other devices on your network from sending payloads to your console.

If you want to use a "normal" ELF Loader that allows sending payloads from any device:
1. Place your `elfldr.elf` in the `ps5_autoloader` directory.
2. Add `elfldr.elf` as the **first** line in your `autoload.txt`.
</details>

<details>
<summary><i>etaHEN loading stability issues</i></summary>

Sometimes etaHEN will fail to load. It seems that etaHEN/kstuff often won't finish loading until the game app is closed.

**Recommended Solution:**
The autoloader includes **Payload Manager**. Using it is the most reliable way to load etaHEN/kstuff, as it waits for the game app to close before sending the payloads. To use it, make `pldmgr.elf` the **only** item in your `autoload.txt`.

**Alternative Workarounds:**
- Disable etaHEN toolbox automatic injecting.
- Load etaHEN without kstuff and then load kstuff separately.
- Minimize the game app (by holding the PS button) after running lapse but before etaHEN loads.
- Add a delay before loading etaHEN to give yourself more time to minimize.
</details>

---

## 🙌 Credits
* shahrilnet – creator and maintainer of the original [remote_lua_loader](https://github.com/shahrilnet/remote_lua_loader)
* excellent blog [post](https://memorycorruption.net/posts/rce-lua-factorio/) where most of the ideas of lua primitives are taken from 
* flatz - for sharing ideas and lua implementations
* null_ptr - for helping to develop umtx exploit for PS5 & numerous helps with the loader development
* gezine - for sharing the vulnerable games & ideas
* specter & chendo - for webkit implementations referenced a lot
* al-azif - parts and information grabbed from his sdk, aswell as from his ftp server
* horror - for the notification popup and ftp server payloads
* ufm42 - for kexp
* everyone else who shared their knowledge with the community

---

## ⚠️ Disclaimer
This tool is provided as-is for research and development purposes only. Use at your own risk. The developers are not responsible for any damage, data loss, or consequences resulting from the use of this software.

---

## 📜 License
This project is licensed under the **GPL-3.0 License**.

The original project by shahrilnet did not include an explicit LICENSE file.  
All unique modifications and additions in this fork are licensed under **GPL-3.0**.

---

## 💖 Donate
- [donate to PLK](DONATE.md)
