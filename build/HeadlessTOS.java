import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.UUID;

import scala.Option;

import totoro.ocelot.brain.Ocelot;
import totoro.ocelot.brain.entity.APU;
import totoro.ocelot.brain.entity.Case;
import totoro.ocelot.brain.entity.DataCard;
import totoro.ocelot.brain.entity.EEPROM;
import totoro.ocelot.brain.entity.HDDManaged;
import totoro.ocelot.brain.entity.InternetCard;
import totoro.ocelot.brain.entity.Keyboard;
import totoro.ocelot.brain.entity.Memory;
import totoro.ocelot.brain.entity.Screen;
import totoro.ocelot.brain.entity.machine.Machine;
import totoro.ocelot.brain.util.ExtendedTier;
import totoro.ocelot.brain.util.Tier;
import totoro.ocelot.brain.workspace.Workspace;

/**
 * Boots TOS on a headless OpenComputers machine and ticks it until it
 * powers itself off. Driven by headless-selftest.py; see its docstring.
 *
 * WHY THIS WORKS. Ocelot Desktop is a window around Ocelot Brain, which is
 * OpenComputers' machine with Minecraft taken out: the same machine.lua, the
 * same native Lua 5.3, the same component code. Its jar carries Brain whole,
 * so a program on the jar's classpath can build a computer, power it on and
 * tick its world without opening a window. Nothing here emulates anything;
 * it is the code Ocelot's GUI runs, minus the GUI.
 *
 *   --boot DIR      the boot disk: a host directory, as Ocelot's disks are
 *   --disk DIR      the test disk (the battery's checks and selftest.on)
 *   --bios FILE     the EEPROM image (TOS-Release/bios.lua)
 *   --work DIR      workspace, extracted Lua natives, screen.txt
 *   --timeout SECS  give up on a machine still running after this long
 *   --config FILE   an OpenComputers.conf (Ocelot's brain.customConfigPath)
 *   --internet      add an internet card (off: 90-internet-absence checks
 *                   the no-card path)
 *
 * Exit: 0 the machine powered itself off, 2 still running at the timeout,
 * 3 it never started, 4 it stopped with an error (a crash, not a shutdown).
 */
public class HeadlessTOS {
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

  public static void main(String[] args) throws Exception {
    String boot = opt(args, "--boot", null), disk = opt(args, "--disk", null);
    String biosFile = opt(args, "--bios", null), workDir = opt(args, "--work", null);
    if (boot == null || disk == null || biosFile == null || workDir == null) {
      System.err.println("usage: HeadlessTOS --boot DIR --disk DIR --bios FILE --work DIR"
          + " [--timeout SECS] [--config FILE] [--internet]");
      System.exit(64);
    }
    Path bootDir = Paths.get(boot).toAbsolutePath();
    Path diskDir = Paths.get(disk).toAbsolutePath();
    byte[] bios = Files.readAllBytes(Paths.get(biosFile));
    Path work = Paths.get(workDir).toAbsolutePath();
    double timeout = Double.parseDouble(opt(args, "--timeout", "240"));
    String config = opt(args, "--config", null);

    Files.createDirectories(work.resolve("libs"));
    Files.createDirectories(work.resolve("ws"));
    Ocelot.librariesPath_$eq(Option.apply(work.resolve("libs")));
    if (config != null) Ocelot.configPath_$eq(Option.apply(Paths.get(config).toAbsolutePath()));
    Ocelot.initialize();

    Workspace ws = new Workspace(work.resolve("ws"));

    // The machine TOS is tested on in Ocelot's window, part for part and
    // slot for slot: a T3 case, a T2 APU on Lua 5.3, two T3.5 sticks, a T3
    // boot disk, a T2 test disk, a T3 data card, a T3 screen, a keyboard.
    // No modem, and no internet card unless asked for.
    Case pc = ws.add(new Case(Tier.Three()));

    String bootAddr = UUID.randomUUID().toString();
    String diskAddr = UUID.randomUUID().toString();
    HDDManaged bootHdd = new HDDManaged(Tier.Three());
    bootHdd.address_$eq(Option.apply(bootAddr));
    bootHdd.customRealPath_$eq(Option.apply(bootDir));
    HDDManaged testHdd = new HDDManaged(Tier.Two());
    testHdd.address_$eq(Option.apply(diskAddr));
    testHdd.customRealPath_$eq(Option.apply(diskDir));

    EEPROM eeprom = new EEPROM();
    eeprom.codeBytes_$eq(Option.apply(bios));
    eeprom.label_$eq("Lua BIOS");
    // The EEPROM's data is the boot address, as the BIOS leaves it.
    eeprom.volatileData_$eq(bootAddr.getBytes(StandardCharsets.UTF_8));

    pc.inventory().apply(0).put(new DataCard.Tier3());
    if (flag(args, "--internet")) pc.inventory().apply(2).put(new InternetCard());
    pc.inventory().apply(3).put(new Memory(ExtendedTier.ThreeHalf()));
    pc.inventory().apply(4).put(new Memory(ExtendedTier.ThreeHalf()));
    pc.inventory().apply(5).put(bootHdd);
    pc.inventory().apply(6).put(testHdd);
    pc.inventory().apply(8).put(new APU(Tier.Two()));
    pc.inventory().apply(9).put(eeprom);

    Screen screen = ws.add(new Screen(Tier.Three()));
    Keyboard keyboard = ws.add(new Keyboard());
    pc.connect(screen);
    screen.connect(keyboard);

    Machine m = pc.machine();
    System.out.println("[headless] boot disk " + bootAddr);
    System.out.println("[headless] test disk " + diskAddr);
    System.out.println("[headless] power on: " + (m.start() ? "ok" : "refused"));

    long start = System.nanoTime();
    long deadline = start + (long) (timeout * 1e9);
    boolean everRan = false;
    int code = 2, tick = 0;
    // The screen goes blank at power-off, so keep the last frame that had
    // anything on it: that is the boot console as the battery left it.
    String lastFrame = "";
    while (System.nanoTime() < deadline) {
      ws.update();
      if (m.isRunning()) everRan = true;
      else if (everRan) { code = 0; break; }
      else if (System.nanoTime() - start > 10_000_000_000L) { code = 3; break; }
      if (++tick % 20 == 0) {
        String f = screenText(screen);
        if (!f.trim().isEmpty()) lastFrame = f;
      }
      Thread.sleep(50);   // 20 TPS, the pace Ocelot Desktop keeps
    }
    String err = m.lastError();
    if (code == 0 && err != null) code = 4;
    System.out.printf("[headless] %s after %.1fs%s%n",
        code == 0 ? "powered off" : code == 2 ? "still running" : code == 3 ? "never started" : "crashed",
        (System.nanoTime() - start) / 1e9, err != null ? (": " + err) : "");

    String now = screenText(screen);
    Files.write(work.resolve("screen.txt"),
        (now.trim().isEmpty() ? lastFrame : now).getBytes(StandardCharsets.UTF_8));

    if (m.isRunning()) m.stop();
    Ocelot.shutdown();
    System.exit(code);
  }
}
