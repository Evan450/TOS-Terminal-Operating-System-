import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardOpenOption;
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.regex.Pattern;

import scala.Option;

import totoro.ocelot.brain.Ocelot;
import totoro.ocelot.brain.entity.APU;
import totoro.ocelot.brain.entity.CPU;
import totoro.ocelot.brain.entity.Case;
import totoro.ocelot.brain.entity.DataCard;
import totoro.ocelot.brain.entity.EEPROM;
import totoro.ocelot.brain.entity.GraphicsCard;
import totoro.ocelot.brain.entity.HDDManaged;
import totoro.ocelot.brain.entity.InternetCard;
import totoro.ocelot.brain.entity.Keyboard;
import totoro.ocelot.brain.entity.Memory;
import totoro.ocelot.brain.entity.Screen;
import totoro.ocelot.brain.entity.machine.Machine;
import totoro.ocelot.brain.user.User;
import totoro.ocelot.brain.util.ExtendedTier;
import totoro.ocelot.brain.util.Tier;
import totoro.ocelot.brain.workspace.Workspace;

/**
 * Boots TOS on a headless OpenComputers machine. Driven by
 * headless-selftest.py (the boot battery) and headless-session.py (a
 * scripted session at the keyboard); see their docstrings.
 *
 * WHY THIS WORKS. Ocelot Desktop is a window around Ocelot Brain, which is
 * OpenComputers' machine with Minecraft taken out: the same machine.lua, the
 * same native Lua 5.3, the same component code. Its jar carries Brain whole,
 * so a program on the jar's classpath can build a computer, power it on and
 * tick its world without opening a window. Nothing here emulates anything;
 * it is the code Ocelot's GUI runs, minus the GUI.
 *
 *   --boot DIR      the boot disk: a host directory, as Ocelot's disks are
 *   --disk DIR      a second disk (the battery's checks, a package floppy)
 *   --bios FILE     the EEPROM image (TOS-Release/bios.lua)
 *   --work DIR      workspace, extracted Lua natives, screens and logs
 *   --timeout SECS  give up on a machine still running after this long
 *   --config FILE   an OpenComputers.conf (Ocelot's brain.customConfigPath)
 *   --profile NAME  t3 (default): the Ocelot test machine. t1: a T1 CPU,
 *                   GPU and screen on one 192K stick, no data card -- the
 *                   smallest box TOS claims to run on
 *   --ram LIST      the memory sticks, in KB, comma-separated: 192, 256,
 *                   384, 512, 768 or 1024 (the six OpenComputers sizes; at
 *                   most two). Default 1024,1024 for t3 and 192 for t1
 *   --boot-tier N   the boot drive's tier, 1-3 (default 3: 4 MB; 2 is 2 MB)
 *   --disk-address U  the second disk's address, so an OS that mounts by
 *                   address (OpenOS: /mnt/<first 3>) puts it somewhere known
 *   --internet      add an internet card
 *   --script FILE   drive the machine: see runScript for the steps
 *   --trace         write every distinct screen to frames.txt
 *
 * Without --script the machine runs until it powers itself off. Exit: 0 it
 * did, 2 still running at the timeout, 3 it never started, 4 it stopped
 * with an error. With --script, 0 means every step completed and 5 that one
 * did not (a wait timed out, or the machine went down mid-script).
 */
public class HeadlessTOS {
  static final User USER = new User("headless");

  static String opt(String[] args, String name, String dflt) {
    for (int i = 0; i + 1 < args.length; i++) if (args[i].equals(name)) return args[i + 1];
    return dflt;
  }

  static boolean flag(String[] args, String name) {
    for (String a : args) if (a.equals(name)) return true;
    return false;
  }

  /** The screen's text, one line per row, trailing blanks trimmed. */
  static String screenText(Screen s) {
    StringBuilder sb = new StringBuilder();
    for (int y = 0; y < s.getHeight(); y++) {
      StringBuilder row = new StringBuilder();
      for (int x = 0; x < s.getWidth(); x++) row.append(s.get(x, y));
      sb.append(row.toString().replaceAll("\\s+$", "")).append('\n');
    }
    return sb.toString();
  }

  /**
   * Each cell's colours, one line per row: "RRGGBB/RRGGBB" (foreground /
   * background) per cell, separated by spaces. A cell coloured from the
   * palette is resolved through it, so this is what the screen shows.
   * Text alone cannot check a syntax colour, a selection or a cursor;
   * this is for checks that need them, not for pictures of the screen.
   */
  static String screenColors(Screen s) {
    StringBuilder sb = new StringBuilder();
    for (int y = 0; y < s.getHeight(); y++) {
      for (int x = 0; x < s.getWidth(); x++) {
        int fg = s.getForegroundColor(x, y);
        if (s.isForegroundFromPalette(x, y)) fg = s.getPaletteColor(fg);
        int bg = s.getBackgroundColor(x, y);
        if (s.isBackgroundFromPalette(x, y)) bg = s.getPaletteColor(bg);
        if (x > 0) sb.append(' ');
        sb.append(String.format("%06x/%06x", fg & 0xffffff, bg & 0xffffff));
      }
      sb.append('\n');
    }
    return sb.toString();
  }

  // ── Keys ──────────────────────────────────────────────────────────
  // OpenComputers' key_down carries a character and an LWJGL key code, and
  // code that checks the code (arrows, F-keys, Ctrl+letter) needs the real
  // one, so typed characters get theirs too.
  static final Map<String, Integer> NAMED = new HashMap<>();
  static final Map<Character, Integer> CODE = new HashMap<>();
  static {
    String[][] named = {
      {"enter", "28"}, {"backspace", "14"}, {"tab", "15"}, {"esc", "1"}, {"space", "57"},
      {"up", "200"}, {"down", "208"}, {"left", "203"}, {"right", "205"},
      {"home", "199"}, {"end", "207"}, {"pgup", "201"}, {"pgdn", "209"},
      {"insert", "210"}, {"delete", "211"}, {"f11", "87"}, {"f12", "88"},
      {"ctrl", "29"}, {"shift", "42"}, {"alt", "56"},
    };
    for (String[] k : named) NAMED.put(k[0], Integer.parseInt(k[1]));
    for (int i = 1; i <= 10; i++) NAMED.put("f" + i, 58 + i);
    String[] rows = {"1234567890-=", "qwertyuiop[]", "asdfghjkl;'`", "\\zxcvbnm,./"};
    String[] shifted = {"!@#$%^&*()_+", "QWERTYUIOP{}", "ASDFGHJKL:\"~", "|ZXCVBNM<>?"};
    int[] first = {2, 16, 30, 43};
    for (int r = 0; r < rows.length; r++)
      for (int i = 0; i < rows[r].length(); i++) {
        CODE.put(rows[r].charAt(i), first[r] + i);
        CODE.put(shifted[r].charAt(i), first[r] + i);
      }
    CODE.put(' ', 57);
  }

  /** The character a named key sends with its code. */
  static char charFor(String name) {
    switch (name) {
      case "enter": return '\r';
      case "backspace": return 8;
      case "tab": return '\t';
      case "esc": return 27;
      case "space": return ' ';
      default: return 0;
    }
  }

  // ── The machine ───────────────────────────────────────────────────
  static Screen screen;
  static Machine machine;
  static Workspace ws;

  static ExtendedTier.ExtendedTierVal stick(String kb) {
    switch (kb.trim()) {
      case "192": return ExtendedTier.One();
      case "256": return ExtendedTier.OneHalf();
      case "384": return ExtendedTier.Two();
      case "512": return ExtendedTier.TwoHalf();
      case "768": return ExtendedTier.Three();
      case "1024": return ExtendedTier.ThreeHalf();
      default: throw new IllegalArgumentException("no " + kb + "K memory stick (192/256/384/512/768/1024)");
    }
  }

  static Tier.TierVal tier(String n) {
    switch (n) {
      case "1": return Tier.One();
      case "2": return Tier.Two();
      case "3": return Tier.Three();
      default: throw new IllegalArgumentException("no drive tier " + n + " (1, 2 or 3)");
    }
  }

  static void build(String profile, Path bootDir, Path diskDir, byte[] bios, boolean internet, String ram,
                    String bootTier, String diskAddress) {
    boolean t1 = profile.equals("t1");
    String[] sticks = (ram != null ? ram : t1 ? "192" : "1024,1024").split(",");
    if (sticks.length > 2) throw new IllegalArgumentException("at most two memory sticks");
    // t3 is the machine TOS is tested on in Ocelot's window, part for part
    // and slot for slot: a T3 case, a T2 APU on Lua 5.3, two T3.5 sticks, a
    // T3 boot disk, a T2 test disk, a T3 data card, a T3 screen. t1 keeps
    // the T3 case and boot disk (a T1 disk cannot hold TOS) and puts T1
    // parts in it. No modem; no internet card unless asked for.
    Case pc = ws.add(new Case(Tier.Three()));

    String bootAddr = UUID.randomUUID().toString();
    HDDManaged bootHdd = new HDDManaged(tier(bootTier));
    bootHdd.address_$eq(Option.apply(bootAddr));
    bootHdd.customRealPath_$eq(Option.apply(bootDir));

    EEPROM eeprom = new EEPROM();
    eeprom.codeBytes_$eq(Option.apply(bios));
    eeprom.label_$eq("Lua BIOS");
    // The EEPROM's data is the boot address, as the BIOS leaves it.
    eeprom.volatileData_$eq(bootAddr.getBytes(StandardCharsets.UTF_8));

    if (!t1) pc.inventory().apply(0).put(new DataCard.Tier3());
    if (internet) pc.inventory().apply(2).put(new InternetCard());
    for (int i = 0; i < sticks.length; i++) pc.inventory().apply(3 + i).put(new Memory(stick(sticks[i])));
    pc.inventory().apply(5).put(bootHdd);
    if (diskDir != null) {
      HDDManaged testHdd = new HDDManaged(Tier.Two());
      testHdd.address_$eq(Option.apply(diskAddress != null ? diskAddress : UUID.randomUUID().toString()));
      testHdd.customRealPath_$eq(Option.apply(diskDir));
      pc.inventory().apply(6).put(testHdd);
      System.out.println("[headless] second disk " + testHdd.address().get());
    }
    if (t1) {
      pc.inventory().apply(1).put(new GraphicsCard(Tier.One()));
      pc.inventory().apply(8).put(new CPU(Tier.One()));
    } else {
      pc.inventory().apply(8).put(new APU(Tier.Two()));
    }
    pc.inventory().apply(9).put(eeprom);

    screen = ws.add(new Screen(t1 ? Tier.One() : Tier.Three()));
    Keyboard keyboard = ws.add(new Keyboard());
    pc.connect(screen);
    screen.connect(keyboard);

    machine = pc.machine();
    System.out.println("[headless] profile " + profile + ", RAM " + String.join("+", sticks)
        + "K, boot disk " + bootAddr);
  }

  // ── Run until it powers itself off ────────────────────────────────
  static int runUntilOff(double timeout, Path work) throws Exception {
    long start = System.nanoTime();
    long deadline = start + (long) (timeout * 1e9);
    boolean everRan = false;
    int code = 2, tick = 0;
    // The screen goes blank at power-off, so keep the last frame that had
    // anything on it: that is the boot console as the battery left it.
    String lastFrame = "";
    while (System.nanoTime() < deadline) {
      ws.update();
      if (machine.isRunning()) everRan = true;
      else if (everRan) { code = 0; break; }
      else if (System.nanoTime() - start > 10_000_000_000L) { code = 3; break; }
      if (++tick % 20 == 0) {
        String f = screenText(screen);
        if (!f.trim().isEmpty()) lastFrame = f;
        trace(work, start, f);
      }
      Thread.sleep(50);   // 20 TPS, the pace Ocelot Desktop keeps
    }
    String err = machine.lastError();
    if (code == 0 && err != null) code = 4;
    System.out.printf("[headless] %s after %.1fs%s%n",
        code == 0 ? "powered off" : code == 2 ? "still running" : code == 3 ? "never started" : "crashed",
        (System.nanoTime() - start) / 1e9, err != null ? (": " + err) : "");
    String now = screenText(screen);
    write(work.resolve("screen.txt"), now.trim().isEmpty() ? lastFrame : now);
    return code;
  }

  static Path tracePath;
  static String lastTraced = "";

  static void trace(Path work, long start, String frame) throws Exception {
    if (tracePath == null || frame.equals(lastTraced)) return;
    lastTraced = frame;
    String head = String.format("=== t=%.1fs%n", (System.nanoTime() - start) / 1e9);
    Files.write(tracePath, (head + frame).getBytes(StandardCharsets.UTF_8),
        StandardOpenOption.CREATE, StandardOpenOption.APPEND);
  }

  static void write(Path p, String s) throws Exception {
    Files.write(p, s.getBytes(StandardCharsets.UTF_8));
  }

  // ── Run a script ──────────────────────────────────────────────────
  /*
   * One step per line; blank lines and # comments are skipped.
   *
   *   wait SECS REGEX     until the screen matches (Java regex, MULTILINE,
   *                       find() over the whole screen); the step fails if
   *                       SECS pass first
   *   gone SECS REGEX     until the screen no longer matches
   *   maybe SECS REGEX    if the screen matches within SECS, the next step
   *                       runs; if not, the next step is skipped. For what
   *                       only sometimes appears (a first-login tour)
   *   type TEXT           types TEXT; \n is Enter, \t Tab, \\ a backslash
   *   key NAME [N]        presses a key N times: enter, esc, tab, backspace,
   *                       up/down/left/right, home, end, pgup, pgdn, insert,
   *                       delete, f1-f12, or ctrl+LETTER / shift+NAME
   *   paste TEXT          a clipboard paste, as middle-click or Shift+Insert
   *   click X Y [BUTTON]  a click on the cell at column X, row Y (1-based)
   *   sleep SECS
   *   mark NAME           start a stopwatch; later waits report time since it
   *   snap NAME           write the screen to snap-NAME.txt, and each
   *                       cell's colours to snap-NAME.colors
   *   off SECS            until the machine powers itself off
   *   powercycle          the power button, off then on: an UNCLEAN stop
   *
   * Every step prints a "[step]" line with its time, which is how a
   * measurement ("how long does pkg sign take on a T1") comes back.
   */
  static int runScript(Path scriptFile, double timeout, Path work) throws Exception {
    List<String> lines = new ArrayList<>();
    for (String raw : Files.readAllLines(scriptFile, StandardCharsets.UTF_8)) {
      String l = raw.trim();
      if (!l.isEmpty() && !l.startsWith("#")) lines.add(l);
    }
    long start = System.nanoTime();
    long deadline = start + (long) (timeout * 1e9);
    Deque<Runnable> input = new ArrayDeque<>();
    Map<String, Long> marks = new HashMap<>();
    String lastMark = null;
    int si = 0, tick = 0, phase = 0;
    boolean skipNext = false;
    long stepStart = System.nanoTime(), downSince = 0;
    boolean everRan = false;
    int code = 2;
    String failure = null;

    while (System.nanoTime() < deadline) {
      ws.update();
      tick++;
      boolean running = machine.isRunning();
      if (running) { everRan = true; downSince = 0; }
      String frame = null;
      if (tick % 5 == 0 && tracePath != null) trace(work, start, frame = screenText(screen));

      // Two input events per tick: fast enough to type a command in a
      // second, slow enough that nothing a human could not do is tested.
      for (int k = 0; k < 2 && !input.isEmpty(); k++) input.poll().run();

      if (si >= lines.size()) { code = 0; break; }
      String line = lines.get(si);
      String[] w = line.split("\\s+", 3);
      String cmd = w[0];
      double secs = w.length > 1 && (cmd.equals("wait") || cmd.equals("gone") || cmd.equals("sleep")
          || cmd.equals("off") || cmd.equals("maybe")) ? Double.parseDouble(w[1]) : 0;
      double inStep = (System.nanoTime() - stepStart) / 1e9;

      // A machine that is down outside off/powercycle has crashed or shut
      // itself down; a reboot from inside TOS comes back within seconds.
      if (!running && everRan && !cmd.equals("off") && !cmd.equals("powercycle")) {
        if (downSince == 0) downSince = System.nanoTime();
        else if (System.nanoTime() - downSince > 5_000_000_000L) {
          failure = "the machine went down" + (machine.lastError() != null ? ": " + machine.lastError() : "");
          break;
        }
      }
      if (!input.isEmpty()) continue;   // finish typing before the next step

      if (skipNext) {
        // The `maybe` before this step did not see its text: skip it.
        skipNext = false;
        System.out.printf("[step] %3d %-60s skipped%n", si + 1,
            line.length() > 60 ? line.substring(0, 57) + "..." : line);
        si++;
        stepStart = System.nanoTime();
        continue;
      }

      boolean done = false;
      String note = "";
      switch (cmd) {
        case "maybe": {
          if (!running) break;
          if (frame == null) frame = screenText(screen);
          if (Pattern.compile(w[2], Pattern.MULTILINE).matcher(frame).find()) {
            done = true;
          } else if (inStep > secs) {
            done = true;
            skipNext = true;
            note = " (not seen: the next step is skipped)";
          }
          break;
        }
        case "wait":
        case "gone": {
          if (!running) break;
          if (frame == null) frame = screenText(screen);
          boolean hit = Pattern.compile(w[2], Pattern.MULTILINE).matcher(frame).find();
          if (hit == cmd.equals("wait")) {
            done = true;
            if (lastMark != null)
              note = String.format(" (%.2fs since mark %s)", (System.nanoTime() - marks.get(lastMark)) / 1e9, lastMark);
          } else if (inStep > secs) {
            failure = String.format("%s timed out after %.0fs: %s", cmd, secs, w[2]);
          }
          break;
        }
        case "type": {
          String text = line.length() > 5 ? line.substring(5) : "";
          for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (c == '\\' && i + 1 < text.length()) {
              char n = text.charAt(++i);
              if (n == 'n') { press(input, "enter"); continue; }
              if (n == 't') { press(input, "tab"); continue; }
              c = n;
            }
            final char ch = c;
            final int code0 = CODE.getOrDefault(Character.toLowerCase(c), CODE.getOrDefault(c, 0));
            input.add(() -> screen.keyDown(ch, code0, USER));
            input.add(() -> screen.keyUp(ch, code0, USER));
          }
          done = true;
          break;
        }
        case "key": {
          int n = w.length > 2 ? Integer.parseInt(w[2]) : 1;
          for (int i = 0; i < n; i++) press(input, w[1]);
          done = true;
          break;
        }
        case "paste": {
          String text = line.length() > 6 ? line.substring(6) : "";
          input.add(() -> screen.clipboard(text, USER));
          done = true;
          break;
        }
        case "click": {
          String[] a = line.split("\\s+");
          double x = Double.parseDouble(a[1]) - 1, y = Double.parseDouble(a[2]) - 1;
          int button = a.length > 3 && a[3].equals("right") ? 1 : 0;
          input.add(() -> screen.mouseDown(x, y, button, USER));
          input.add(() -> screen.mouseUp(x, y, button, USER));
          done = true;
          break;
        }
        case "sleep":
          done = inStep >= secs;
          break;
        case "mark":
          marks.put(w[1], System.nanoTime());
          lastMark = w[1];
          done = true;
          break;
        case "snap":
          write(work.resolve("snap-" + w[1] + ".txt"), screenText(screen));
          write(work.resolve("snap-" + w[1] + ".colors"), screenColors(screen));
          done = true;
          break;
        case "off":
          if (!running && everRan) done = true;
          else if (inStep > secs) failure = String.format("off timed out after %.0fs", secs);
          break;
        case "powercycle":
          if (phase == 0) { machine.stop(); phase = 1; }
          else if (phase == 1 && !running) { machine.start(); phase = 2; }
          else if (phase == 2 && running) { phase = 0; done = true; }
          else if (inStep > 20) failure = "powercycle: the machine did not come back";
          break;
        default:
          failure = "unknown step: " + line;
      }
      if (failure != null) break;
      if (done) {
        System.out.printf("[step] %3d %-60s ok at %.1fs, %.2fs%s%n", si + 1,
            line.length() > 60 ? line.substring(0, 57) + "..." : line,
            (System.nanoTime() - start) / 1e9, inStep, note);
        si++;
        stepStart = System.nanoTime();
      }
      Thread.sleep(50);
    }
    if (failure == null && code != 0) failure = "the script did not finish before the timeout";
    if (failure != null) {
      code = 5;
      System.out.printf("[step] %3d FAILED: %s%n", si + 1, failure);
      write(work.resolve("fail-screen.txt"), screenText(screen));
    }
    write(work.resolve("screen.txt"), screenText(screen));
    return code;
  }

  static void press(Deque<Runnable> input, String spec) {
    String[] parts = spec.toLowerCase().split("\\+");
    String key = parts[parts.length - 1];
    List<Integer> mods = new ArrayList<>();
    for (int i = 0; i < parts.length - 1; i++) mods.add(NAMED.get(parts[i]));
    int code;
    char ch;
    if (NAMED.containsKey(key)) { code = NAMED.get(key); ch = charFor(key); }
    else if (key.length() == 1) { code = CODE.getOrDefault(key.charAt(0), 0); ch = key.charAt(0); }
    else throw new IllegalArgumentException("unknown key: " + spec);
    // Ctrl+letter sends the control character, as LWJGL reports it.
    if (parts.length > 1 && parts[0].equals("ctrl") && ch >= 'a' && ch <= 'z') ch = (char) (ch - 'a' + 1);
    final char c = ch;
    for (int m : mods) input.add(() -> screen.keyDown((char) 0, m, USER));
    input.add(() -> screen.keyDown(c, code, USER));
    input.add(() -> screen.keyUp(c, code, USER));
    for (int i = mods.size() - 1; i >= 0; i--) {
      int m = mods.get(i);
      input.add(() -> screen.keyUp((char) 0, m, USER));
    }
  }

  public static void main(String[] args) throws Exception {
    String boot = opt(args, "--boot", null), disk = opt(args, "--disk", null);
    String biosFile = opt(args, "--bios", null), workDir = opt(args, "--work", null);
    if (boot == null || biosFile == null || workDir == null) {
      System.err.println("usage: HeadlessTOS --boot DIR --bios FILE --work DIR [--disk DIR]"
          + " [--timeout SECS] [--config FILE] [--profile t3|t1] [--ram KB[,KB]] [--boot-tier N]"
          + " [--disk-address UUID] [--internet]"
          + " [--script FILE] [--trace]");
      System.exit(64);
    }
    Path bootDir = Paths.get(boot).toAbsolutePath();
    Path diskDir = disk != null ? Paths.get(disk).toAbsolutePath() : null;
    byte[] bios = Files.readAllBytes(Paths.get(biosFile));
    Path work = Paths.get(workDir).toAbsolutePath();
    double timeout = Double.parseDouble(opt(args, "--timeout", "240"));
    String config = opt(args, "--config", null);
    String profile = opt(args, "--profile", "t3");
    if (!profile.equals("t3") && !profile.equals("t1")) {
      System.err.println("unknown profile: " + profile);
      System.exit(64);
    }
    String script = opt(args, "--script", null);
    if (flag(args, "--trace")) tracePath = work.resolve("frames.txt");

    Files.createDirectories(work.resolve("libs"));
    Files.createDirectories(work.resolve("ws"));
    Ocelot.librariesPath_$eq(Option.apply(work.resolve("libs")));
    if (config != null) Ocelot.configPath_$eq(Option.apply(Paths.get(config).toAbsolutePath()));
    Ocelot.initialize();

    ws = new Workspace(work.resolve("ws"));
    build(profile, bootDir, diskDir, bios, flag(args, "--internet"), opt(args, "--ram", null),
        opt(args, "--boot-tier", "3"), opt(args, "--disk-address", null));
    System.out.println("[headless] power on: " + (machine.start() ? "ok" : "refused"));

    int code = script != null ? runScript(Paths.get(script), timeout, work) : runUntilOff(timeout, work);
    if (machine.isRunning()) machine.stop();
    Ocelot.shutdown();
    System.exit(code);
  }
}
