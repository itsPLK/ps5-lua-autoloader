<h1 align="center">PS5 Lua Autoloader</h1>
<h3 align="center">Fork of <a href="https://github.com/shahrilnet/remote_lua_loader">remote_lua_loader</a></h3>
&nbsp;
<p align="center">Automatically loads your .elf, .bin and .lua payloads.<br>Supports PS5 firmwares up to 10.01.</p>

<p align="center">
    <b>Other Autoloaders:</b><br>
    <a href="https://github.com/itsPLK/ps5-y2jb-autoloader">PS5 Y2JB Autoloader</a> | 
    <a href="https://github.com/itsPLK/ps5-bdjb-autoloader">PS5 BD-JB Autoloader</a>
</p>



## How to use

There are two ways to use the autoloader:

### 🟢 Option 1: Payload Manager

If no `autoload.txt` config is found, the autoloader will automatically launch **[Payload Manager](https://github.com/itsPLK/ps5-payload-manager)** — a fully-featured PS5 payload manager with a web UI. This lets you configure and send payloads directly from your browser, without needing to manually set up config files or transfer ELF files ahead of time.

Just run the autoloader — if there's nothing configured, Payload Manager starts automatically.

> **Note:** Payload Manager also has its own built-in autoload feature, which lets you configure payloads to load automatically on startup — all managed through its web UI. This is separate from the `autoload.txt` mechanism described below.

---

### ⚙️ Option 2: Manual Config (`autoload.txt`)

For a fixed, automated payload chain, you can configure payloads manually:

* Create a directory named `ps5_autoloader`.
* Inside this directory, place your `.elf` / `.bin` files, and an `autoload.txt` file.
    * In autoload.txt, list the files you want to load (one per line).
    * Filenames are case-sensitive - make sure the names exactly match your files.
    * You can add lines like `!1000` to make the loader wait 1000ms before sending the next payload.
* Put the `ps5_autoloader` directory in one of these locations:
    * In the root of a USB drive
    * In the internal drive at `/data/ps5_autoloader`
* Import savedata to your game:  
  Follow the steps in [SETUP.md](SETUP.md) to prepare and import the savedata for your Lua-compatible game.

> **Note:** When an `autoload.txt` config is found, Payload Manager is **not** launched automatically. If you also want Payload Manager available, place `pldmgr.elf` in your `ps5_autoloader` directory and add it to `autoload.txt`.

## Game Compatibility

Currently this loader is compatible with the following games:
  
| Game Title                                     | TITLE ID   |
|------------------------------------------------|------------|
| Aerial Life                                    | CUSA17122  |
| Aibeya                                         | CUSA17068  |
| Aikagi 2                                       | CUSA19556  |
| Aikagi Kimi to Issho ni Pack                   | CUSA16229  |
| Fuyu Kiss                                      | CUSA29745  |
| Fuyu Kiss Demo                                 | CUSA29746  |
| Hamidashi Creative                             | CUSA27389  |
| Hamidashi Creative Demo                        | CUSA27390  |
| Haruoto Alice Gram Snow Drop                   | CUSA14324  |
| IxSHE Tell                                     | CUSA17112  |
| IxSHE Tell Demo                                | CUSA17126  |
| Jinki Resurrection                             | CUSA25179  |
| Jinki Resurrection Demo                        | CUSA25180  |
| Mikagami Sumika no Seifuku Katsudou            | CUSA11481  |
| Nora Princess and Crying Cat 2                 | CUSA13586  |
| Nora Princess and Stray Cat Heart HD           | CUSA13303  |
| Raspberry Cube                                 | CUSA16074  |
| Tonari ni Kanojo no Iru Shiawase Winter Guest  | CUSA11977  |

**Note**:  Demos require latest firmware to download from PSN

## Updating Savedata

If you have the savedata setup and want to update the files, please refer to [UPDATE.md](UPDATE.md).


## Additional Info

<Details>
<Summary><i>How to use custom ELF Loader version?</i></Summary>

By default, the autoloader uses a custom version of **elfldr** that only accepts connections from the PS5 itself (localhost). This improves security by preventing other devices on your network from sending payloads to your console.

If you want to use a "normal" ELF Loader that allows sending payloads from any device:
1. Place your custom ELF Loader (e.g. `elfldr.elf`) in the `ps5_autoloader` directory.
2. Add `elfldr.elf` to your `autoload.txt`.
3. **Note**: If you are loading other payloads right after `elfldr.elf` in your `autoload.txt`, add a sleep command immediately after it (like `!4000` to sleep for 4 seconds) to give the new ELF Loader time to start up and listen before subsequent payloads are sent.

Example `autoload.txt`:
```text
# Load custom ELF Loader
elfldr.elf
# Give it 4 seconds to start up (only needed if sending more payloads)
!4000
# Send other payloads
ftpsrv.elf
```
</Details>


## Credits

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

## Disclaimer

This tool is provided as-is for research and development purposes only. Use at your own risk. The developers are not responsible for any damage, data loss, or consequences resulting from the use of this software.


## License

This project is licensed under the **GPL-3.0 License**.

The original project by shahrilnet did not include an explicit LICENSE file.  
All unique modifications and additions in this fork are licensed under **GPL-3.0**.

## Donate
- [donate to PLK](DONATE.md)
