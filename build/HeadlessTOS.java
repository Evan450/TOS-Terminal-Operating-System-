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
import java.util.Random;
import java.util.regex.Pattern;

import scala.Option;

import totoro.ocelot.brain.Ocelot;
import totoro.ocelot.brain.entity.APU;
import totoro.ocelot.brain.entity.CPU;
import totoro.ocelot.brain.entity.Case;
import totoro.ocelot.brain.entity.DataCard;
import totoro.ocelot.brain.entity.EEPROM;
import totoro.ocelot.brain.entity.FloppyDiskDrive;
import totoro.ocelot.brain.entity.FloppyManaged;
import totoro.ocelot.brain.entity.GraphicsCard;
import totoro.ocelot.brain.entity.HDDManaged;
import totoro.ocelot.brain.entity.HDDUnmanaged;
import totoro.ocelot.brain.entity.InternetCard;
import totoro.ocelot.brain.entity.Keyboard;
import totoro.ocelot.brain.entity.Memory;
import totoro.ocelot.brain.entity.NoteBlock;
import totoro.ocelot.brain.entity.machine.Arguments;
import totoro.ocelot.brain.entity.machine.Callback;
import totoro.ocelot.brain.entity.machine.Context;
import totoro.ocelot.brain.entity.NetworkCard;
import totoro.ocelot.brain.entity.Relay;
import totoro.ocelot.brain.entity.Screen;
import totoro.ocelot.brain.entity.TapeDrive;
import totoro.ocelot.brain.entity.WirelessNetworkCard;
import totoro.ocelot.brain.entity.tape.Tape;
import totoro.ocelot.brain.network.Network;
import totoro.ocelot.brain.network.Node;
import totoro.ocelot.brain.network.Visibility;
import totoro.ocelot.brain.entity.machine.Machine;
import totoro.ocelot.brain.util.Direction$;
import totoro.ocelot.brain.event.BeepEvent;
import totoro.ocelot.brain.event.BeepPatternEvent;
import totoro.ocelot.brain.event.Event;
import totoro.ocelot.brain.event.EventBus;
import totoro.ocelot.brain.user.User;
import totoro.ocelot.brain.util.DyeColor;
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
 *   --disk2 DIR     a third disk (--disk2-address U, --disk2-tier N: 1-3, default 2)
 *   --internet      add an internet card
 *   --tape          a Computronics tape drive beside the (first) computer,
 *                   with a blank iron tape in it
 *   --peer-boot DIR a SECOND computer booting DIR: its own T3 case, disk,
 *                   screen and keyboard, a network card in each machine and
 *                   a relay between them; the script's `machine N` step
 *                   picks which one the steps after it type at and read
 *   --peer-disk DIR a second disk in the second computer, as --disk is in
 *                   the first (address 5e550000-...-000000000002, so TOS
 *                   mounts it at /mnt/disk_5e55 there too)
 *   --seats N       1 (default) or 2: a second GPU, screen and keyboard,
 *                   so TOS runs two seats; the script's `seat N` step
 *                   picks which screen the steps after it type at and read
 *   --floppy NAME=DIR  a floppy labelled NAME over a host directory
 *                   (repeatable). Any floppy adds one disk drive; TOS
 *                   mounts a labelled disk at /mnt/NAME
 *   --floppy-in NAME   the floppy in the drive at power-on (default: none)
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

  /** Every value of a repeatable option, in order. */
  static List<String> opts(String[] args, String name) {
    List<String> out = new ArrayList<>();
    for (int i = 0; i + 1 < args.length; i++) if (args[i].equals(name)) out.add(args[i + 1]);
    return out;
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

  /** TEXT with each ${NAME} replaced by what `grab NAME` took. */
  static String expand(String text, Map<String, String> vars) {
    for (Map.Entry<String, String> e : vars.entrySet())
      text = text.replace("${" + e.getKey() + "}", e.getValue());
    return text;
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
  static Screen screen;   // the one the script is typing at and reading
  static final List<Screen> screens = new ArrayList<>();   // by seat, for `seat N`
  // --peer-boot, once per extra computer: `machine 2` is the first of these.
  static final List<Machine> peers = new ArrayList<>();
  static final List<Screen> peerScreens = new ArrayList<>();
  static List<String> peerDiskDirs = new ArrayList<>();  // --peer-disk, by peer
  static boolean withTape;      // --tape
  static boolean withGeolyzer;  // --geolyzer
  static String chipFile, chipData;   // --chip, --chip-data
  static StandInRobot chipRobot;
  static boolean withRobot;     // --robot
  static boolean withChest;     // --robot-chest
  static boolean withRubbish;   // --robot-rubbish
  static boolean withTransposer; // --transposer

  /**
   * A transposer with one chest, to the north, holding 20 cobblestone and a
   * glass block. What it is for is the real peripheral.inventory library, and
   * the capability check in front of it, which only a package installed on a
   * real machine goes through. A NoteBlock for the reason Geolyzer is.
   */
  public static class StandInTransposer extends NoteBlock {
    private Node transposerNode;
    private static final String[] NAMES = { "minecraft:cobblestone", "minecraft:glass" };
    private static final int[] SIZES = { 20, 1 };

    @Override public Node node() {
      if (transposerNode == null) {
        transposerNode = Network.newNode(this, Visibility.Network(), Network.newNode$default$3())
            .withComponent("transposer").create();
      }
      return transposerNode;
    }

    @Callback public Object[] getInventorySize(Context context, Arguments args) {
      if (args.checkInteger(0) != 2) return new Object[] { null, "no inventory" };
      return new Object[] { 27 };
    }

    @Callback public Object[] getStackInSlot(Context context, Arguments args) {
      int side = args.checkInteger(0), slot = args.checkInteger(1) - 1;
      if (side != 2 || slot >= NAMES.length) return new Object[] { null };
      Map<String, Object> stack = new HashMap<>();
      stack.put("name", NAMES[slot]);
      stack.put("label", NAMES[slot]);
      stack.put("damage", 0);
      stack.put("size", SIZES[slot]);
      stack.put("maxSize", 64);
      return new Object[] { stack };
    }
  }

  /**
   * A stand-in for the robot component, for what a prefab export does on a
   * real OpenOS. It keeps the shape of OpenComputers 1.8.10's Robot and Agent:
   * move and place return nil and a reason, and a block needs a neighbour of
   * its cell. A robot's turns are its own, starting facing +X. Every block
   * placed is printed as "[headless] robot placed x y z", in cells from where it began,
   * so a run can be checked against the blueprint. A NoteBlock for the reason
   * Geolyzer below is.
   *
   * With --robot-chest it starts empty, with StandInController fitted and a
   * chest right behind it holding 64 cobblestone, 64 dirt and 10 glass.
   * With --robot-rubbish it has a pickaxe, and four blocks are in the way of
   * the test hut, one of them above its first move.
   */
  public static class StandInRobot extends NoteBlock {
    private Node robotNode;
    int x = 0, y = 0, z = 0;
    private int facing = 0, selected = 1;
    final int[] items = new int[17];
    final String[] names = new String[17];
    private final Map<String, Integer> cells = new HashMap<>();
    private final java.util.Set<String> rubbish = new java.util.HashSet<>(
        withRubbish ? java.util.Arrays.asList("0,1,0", "2,0,1", "3,1,2", "4,2,0")
                    : java.util.Collections.<String>emptyList());
    private static final int[] DX = { 1, 0, -1, 0 }, DZ = { 0, 1, 0, -1 };
    final String[] chestNames = { "minecraft:cobblestone", "minecraft:dirt", "minecraft:glass" };
    final int[] chestSizes = { 64, 64, 10 };

    public StandInRobot() {
      if (!withChest) java.util.Arrays.fill(items, 64);
      if (!withChest) java.util.Arrays.fill(names, "any");
    }

    boolean overChest() { return withChest && x == -1 && y == 1 && z == 0; }
    int selected() { return selected; }

    @Override public Node node() {
      if (robotNode == null) {
        robotNode = Network.newNode(this, Visibility.Network(), Network.newNode$default$3())
            .withComponent("robot").create();
      }
      return robotNode;
    }

    private boolean solid(int cx, int cy, int cz) {
      if (withChest && cx == -1 && cy == 0 && cz == 0) return true;
      if (rubbish.contains(cx + "," + cy + "," + cz)) return true;
      return cy < 0 || cells.containsKey(cx + "," + cy + "," + cz);
    }

    /** The cell on a side, as { x, y, z }. */
    private int[] on(int side) {
      if (side == 0) return new int[] { x, y - 1, z };
      if (side == 1) return new int[] { x, y + 1, z };
      if (side == 3) return new int[] { x + DX[facing], y, z + DZ[facing] };
      throw new IllegalArgumentException("no such side here");
    }

    @Callback public Object[] durability(Context context, Arguments args) {
      return withRubbish ? new Object[] { 0.9 } : new Object[] { null, "no tool equipped" };
    }

    @Callback public Object[] swing(Context context, Arguments args) {
      int[] c = on(args.checkInteger(0));
      String key = c[0] + "," + c[1] + "," + c[2];
      if (cells.containsKey(key)) throw new IllegalStateException("it dug what it built: " + key);
      if (!rubbish.remove(key)) return new Object[] { false, "air" };
      for (int i = 0; i < 16; i++) {
        int s = (selected - 1 + i) % 16 + 1;
        if (items[s] == 0 || "minecraft:gravel".equals(names[s])) {
          items[s]++;
          names[s] = "minecraft:gravel";
          break;
        }
      }
      System.out.println("[headless] robot dug " + key);
      return new Object[] { true, "block" };
    }

    @Callback public Object[] space(Context context, Arguments args) {
      return new Object[] { 64 - items[args.count() > 0 ? args.checkInteger(0) : selected] };
    }

    @Callback public Object[] drop(Context context, Arguments args) {
      System.out.println("[headless] robot dropped " + items[selected] + " " + names[selected]);
      items[selected] = 0;
      return new Object[] { true };
    }

    @Callback public Object[] move(Context context, Arguments args) {
      int side = args.checkInteger(0);
      int nx = x, ny = y, nz = z;
      if (side == 0) ny--;
      else if (side == 1) ny++;
      else if (side == 3) { nx += DX[facing]; nz += DZ[facing]; }
      else if (side == 2) { nx -= DX[facing]; nz -= DZ[facing]; }
      else throw new IllegalArgumentException("invalid side");
      if (solid(nx, ny, nz)) return new Object[] { null, "solid" };
      x = nx; y = ny; z = nz;
      return new Object[] { true };
    }

    @Callback public Object[] turn(Context context, Arguments args) {
      facing = (facing + (args.checkBoolean(0) ? 1 : 3)) % 4;
      return new Object[] { true };
    }

    @Callback public Object[] select(Context context, Arguments args) {
      if (args.count() > 0) selected = args.checkInteger(0);
      return new Object[] { selected };
    }

    @Callback public Object[] count(Context context, Arguments args) {
      return new Object[] { items[args.count() > 0 ? args.checkInteger(0) : selected] };
    }

    @Callback public Object[] inventorySize(Context context, Arguments args) {
      return new Object[] { 16 };
    }

    @Callback public Object[] detect(Context context, Arguments args) {
      int[] c = on(args.checkInteger(0));
      boolean there = solid(c[0], c[1], c[2]);
      return new Object[] { there, there ? "solid" : "air" };
    }

    @Callback public Object[] place(Context context, Arguments args) {
      if (args.checkInteger(0) != 0) throw new IllegalArgumentException("only down here");
      if (items[selected] == 0) return new Object[] { false, "nothing selected" };
      int ty = y - 1;
      if (solid(x, ty, z)) return new Object[] { false };
      if (!(solid(x - 1, ty, z) || solid(x + 1, ty, z) || solid(x, ty, z - 1)
          || solid(x, ty, z + 1) || solid(x, ty - 1, z))) return new Object[] { false };
      cells.put(x + "," + ty + "," + z, selected);
      items[selected]--;
      System.out.println("[headless] robot placed " + x + " " + ty + " " + z + " slot " + selected
          + " " + names[selected]);
      return new Object[] { true };
    }
  }

  /** The inventory controller in that robot, reading the chest under it. */
  public static class StandInController extends NoteBlock {
    private Node controllerNode;
    private final StandInRobot robot;

    public StandInController(StandInRobot robot) { this.robot = robot; }

    @Override public Node node() {
      if (controllerNode == null) {
        controllerNode = Network.newNode(this, Visibility.Network(), Network.newNode$default$3())
            .withComponent("inventory_controller").create();
      }
      return controllerNode;
    }

    @Callback public Object[] getInventorySize(Context context, Arguments args) {
      if (args.checkInteger(0) != 0 || !robot.overChest()) return new Object[] { null, "no inventory" };
      return new Object[] { 27 };
    }

    @Callback public Object[] getStackInSlot(Context context, Arguments args) {
      int side = args.checkInteger(0), slot = args.checkInteger(1) - 1;
      if (side != 0 || !robot.overChest() || slot >= robot.chestSizes.length
          || robot.chestSizes[slot] == 0) return new Object[] { null };
      Map<String, Object> stack = new HashMap<>();
      stack.put("name", robot.chestNames[slot]);
      stack.put("label", robot.chestNames[slot]);
      stack.put("damage", 0);
      stack.put("size", robot.chestSizes[slot]);
      stack.put("maxSize", 64);
      return new Object[] { stack };
    }

    @Callback public Object[] getStackInInternalSlot(Context context, Arguments args) {
      int slot = args.count() > 0 ? args.checkInteger(0) : robot.selected();
      if (robot.items[slot] == 0) return new Object[] { null };
      Map<String, Object> stack = new HashMap<>();
      stack.put("name", robot.names[slot]);
      stack.put("damage", 0);
      stack.put("size", robot.items[slot]);
      return new Object[] { stack };
    }

    @Callback public Object[] suckFromSlot(Context context, Arguments args) {
      int side = args.checkInteger(0), slot = args.checkInteger(1) - 1;
      int want = args.optInteger(2, 64), to = robot.selected();
      if (side != 0 || !robot.overChest() || slot >= robot.chestSizes.length) return new Object[] { false };
      String item = robot.chestNames[slot];
      if (robot.items[to] > 0 && !item.equals(robot.names[to])) return new Object[] { false };
      int n = Math.min(want, Math.min(robot.chestSizes[slot], 64 - robot.items[to]));
      if (n <= 0) return new Object[] { false };
      robot.chestSizes[slot] -= n;
      robot.items[to] += n;
      robot.names[to] = item;
      System.out.println("[headless] robot took " + n + " " + item);
      return new Object[] { true };
    }
  }

  /**
   * Ocelot Brain has no geolyzer, and a headless machine has no world, so
   * this stands in for both. scan follows OpenComputers 1.8.10 to the letter
   * (Geolyzer.scan, EventHandlerVanilla.onGeolyzerScan): 64 floats whatever
   * is asked, filled with noise first so anything past the box is NOT zero,
   * then exactly 0 for air and noise * distance * 2 + hardness for a block.
   * What it is for is the part a fake in Lua cannot show: a real component
   * through TOS's real sandbox and proxy, on the real Lua VM.
   *
   * It is a NoteBlock because Ocelot's traits carry state a Java class cannot
   * implement; node() is swapped so the machine sees a geolyzer.
   */
  public static class Geolyzer extends NoteBlock {
    private Node geoNode;
    private final Random random = new Random(1);

    @Override public Node node() {
      if (geoNode == null) {
        geoNode = Network.newNode(this, Visibility.Network(), Network.newNode$default$3())
            .withComponent("geolyzer").create();
      }
      return geoNode;
    }

    /** Hardness at an offset from the geolyzer, or null for air: grass at
     *  y -1 over stone, a pond, a tree, and a pit. */
    static Float world(int x, int y, int z) {
      if (x == 2 && z == 2 && y >= 0 && y <= 3) return 2f;
      if (x >= 1 && x <= 3 && z >= 1 && z <= 3 && y >= 3 && y <= 4) return 0.2f;
      if (x == -3 && z == -2 && y == -1) return 100f;
      if (x == -1 && z == 2 && y >= -3 && y <= -1) return null;
      if (y == -1) return 0.6f;
      return y < -1 ? 1.5f : null;
    }

    @Callback(doc = "function(x:number, z:number, y:number, w:number, d:number, h:number):table")
    public Object[] scan(Context context, Arguments args) {
      int x = args.checkInteger(0), z = args.checkInteger(1), y = args.checkInteger(2);
      int w = args.checkInteger(3), d = args.checkInteger(4), h = args.checkInteger(5);
      if (w * d * h > 64) throw new IllegalArgumentException("volume too large (maximum is 64)");
      int maxX = x + w - 1, maxY = y + h - 1, maxZ = z + d - 1;
      for (int n : new int[] { x, y, z, maxX, maxY, maxZ }) {
        if (Math.abs(n) > 32) throw new IllegalArgumentException("location out of bounds");
      }
      byte[] noise = new byte[64];
      random.nextBytes(noise);
      float[] data = new float[64];
      for (int i = 0; i < 64; i++) data[i] = noise[i] / 128f / 33f;
      for (int ry = y; ry <= maxY; ry++) {
        for (int rz = z; rz <= maxZ; rz++) {
          for (int rx = x; rx <= maxX; rx++) {
            int i = (rx - x) + ((rz - z) + (ry - y) * d) * w;
            Float hard = world(rx, ry, rz);
            float dist = (float) Math.sqrt(rx * rx + ry * ry + rz * rz);
            data[i] = hard == null ? 0f : data[i] * dist * 2f + hard;
          }
        }
      }
      return new Object[] { data };
    }
  }
  static Machine machine;
  static Workspace ws;
  static Case pcCase;      // for `pullcard`
  static Path bootPath;   // the boot disk's host directory, for `hostmv`
  // The disk drive and the floppies a script can swap through it, by name.
  static FloppyDiskDrive floppyDrive;
  // A THIRD disk (--disk2), so an installer run from OpenOS can have a boot
  // drive, an install source and somewhere else to put TOS.
  static Path disk2Dir;
  static String disk2Address, disk2Tier = "2";
  static final Map<String, FloppyManaged> floppies = new java.util.LinkedHashMap<>();
  static boolean readOnlyBoot;
  static boolean rawDrive;

  /**
   * A floppy labelled `name` over host directory `dir`, at an address fixed
   * by its name -- the same floppy on every run, and every re-insert, as a
   * real one would be.
   */
  static FloppyManaged floppy(String name, Path dir) {
    FloppyManaged f = new FloppyManaged(Option.apply(name), DyeColor.Gray());
    f.address_$eq(Option.apply(
        UUID.nameUUIDFromBytes(("tos-headless-floppy:" + name).getBytes(StandardCharsets.UTF_8)).toString()));
    f.customRealPath_$eq(Option.apply(dir));
    // The constructor's Option is not the label; this is (and TOS mounts a
    // labelled disk at /mnt/<label>).
    f.label().setLabel(name);
    return f;
  }

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
                    String bootTier, String diskAddress, List<String> floppySpecs, String floppyIn,
                    int seats, List<String> peerBoots) {
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
    // Locked is what makes OC hand back a read-only filesystem, as for a loot disk.
    if (readOnlyBoot) bootHdd.setLocked("headless");

    EEPROM eeprom = new EEPROM();
    eeprom.codeBytes_$eq(Option.apply(bios));
    eeprom.label_$eq("Lua BIOS");
    // The EEPROM's data is the boot address, as the BIOS leaves it.
    eeprom.volatileData_$eq(bootAddr.getBytes(StandardCharsets.UTF_8));

    if (!t1) pc.inventory().apply(0).put(new DataCard.Tier3());
    pcCase = pc;
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
    if (disk2Dir != null) {
      HDDManaged hdd2 = new HDDManaged(tier(disk2Tier));
      hdd2.address_$eq(Option.apply(disk2Address != null ? disk2Address : UUID.randomUUID().toString()));
      hdd2.customRealPath_$eq(Option.apply(disk2Dir));
      pc.inventory().apply(7).put(hdd2);
      System.out.println("[headless] third disk " + hdd2.address().get());
    }
    // Unmanaged: no filesystem, just sectors, for TBFS. Takes the third disk's slot.
    if (rawDrive) {
      HDDUnmanaged raw = new HDDUnmanaged(Tier.Two());
      pc.inventory().apply(7).put(raw);
      System.out.println("[headless] raw drive " + raw.node().address());
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
    screens.add(screen);
    // A second seat: its own GPU (t3's APU leaves card slot 1 free; t1 has
    // no data card, so slot 0), screen and keyboard. TOS pairs GPUs with
    // screens at boot and runs a login on each.
    if (seats == 2) {
      pc.inventory().apply(t1 ? 0 : 1).put(new GraphicsCard(t1 ? Tier.One() : Tier.Three()));
      Screen second = ws.add(new Screen(t1 ? Tier.One() : Tier.Three()));
      Keyboard keyboard2 = ws.add(new Keyboard());
      pc.connect(second);
      second.connect(keyboard2);
      screens.add(second);
    }

    // A disk drive beside the case, as in the world: the floppies are swapped
    // through it by the script's `eject` / `insert NAME` steps.
    if (!floppySpecs.isEmpty()) {
      floppyDrive = ws.add(new FloppyDiskDrive());
      pc.connect(floppyDrive);
      for (String spec : floppySpecs) {
        int eq = spec.indexOf('=');
        if (eq <= 0) throw new IllegalArgumentException("--floppy takes NAME=DIR: " + spec);
        String name = spec.substring(0, eq);
        floppies.put(name, floppy(name, Paths.get(spec.substring(eq + 1)).toAbsolutePath()));
        System.out.println("[headless] floppy " + name + " " + floppies.get(name).address().get());
      }
      if (floppyIn != null) {
        FloppyManaged f = floppies.get(floppyIn);
        if (f == null) throw new IllegalArgumentException("--floppy-in names no --floppy: " + floppyIn);
        floppyDrive.inventory().apply(0).put(f);
      }
    }

    // A tape drive (--tape), as a player would put one beside the case.
    if (withTape) {
      TapeDrive drive = ws.add(new TapeDrive());
      pc.connect(drive);
      drive.inventory().apply(0).put(new Tape(Tape.Kind$.MODULE$.Iron(), Option.apply("intercom")));
      System.out.println("[headless] tape drive with a blank iron tape");
    }

    // A geolyzer (--geolyzer), over the small site in Geolyzer.world.
    if (withGeolyzer) {
      Geolyzer geo = ws.add(new Geolyzer());
      pc.connect(geo);
      System.out.println("[headless] geolyzer " + geo.node().address());
    }

    // A robot (--robot): this machine answers as one, for an exported build.
    if (withRobot) {
      StandInRobot robot = ws.add(new StandInRobot());
      pc.connect(robot);
      System.out.println("[headless] robot " + robot.node().address());
      if (withChest) {
        StandInController controller = ws.add(new StandInController(robot));
        pc.connect(controller);
      }
    }

    // A transposer (--transposer), with a chest to read.
    if (withTransposer) {
      StandInTransposer transposer = ws.add(new StandInTransposer());
      pc.connect(transposer);
      System.out.println("[headless] transposer " + transposer.node().address());
    }

    // More computers (--peer-boot): each with its own case, disk, screen and
    // keyboard, a network card in every machine, and a RELAY joining them --
    // the block a player puts between two computers so that packets cross
    // and components do not. One cable would merge their component
    // networks, and each would see (and bind) the other's screen.
    if (!peerBoots.isEmpty()) {
      // The card slot nothing else took: t3's APU leaves slot 1 free, t1's
      // GPU is IN slot 1 and leaves slot 0 (no data card), and a second
      // seat's GPU takes that one, which leaves slot 2. Slot 1 for both
      // profiles put the network card over t1's only GPU, and the machine
      // shut down at boot with "0 GPUs".
      int slot = seats == 2 ? 2 : t1 ? 0 : 1;
      if (slot == 2 && internet)
        throw new IllegalArgumentException("--peer-boot with --seats 2 and --internet: no free card slot");
      pc.inventory().apply(slot).put(new NetworkCard());
      Relay relay = ws.add(new Relay());
      relay.connect(Direction$.MODULE$.North(), pc);
      for (int i = 0; i < peerBoots.size(); i++) {
        Path peerBoot = Paths.get(peerBoots.get(i)).toAbsolutePath();
        Case pc2 = ws.add(new Case(Tier.Three()));
        String addr2 = UUID.randomUUID().toString();
        HDDManaged hdd2 = new HDDManaged(tier(bootTier));
        hdd2.address_$eq(Option.apply(addr2));
        hdd2.customRealPath_$eq(Option.apply(peerBoot));
        EEPROM eeprom2 = new EEPROM();
        eeprom2.codeBytes_$eq(Option.apply(bios));
        eeprom2.label_$eq("Lua BIOS");
        eeprom2.volatileData_$eq(addr2.getBytes(StandardCharsets.UTF_8));
        pc2.inventory().apply(0).put(new DataCard.Tier3());
        pc2.inventory().apply(1).put(new NetworkCard());
        pc2.inventory().apply(3).put(new Memory(stick("1024")));
        pc2.inventory().apply(4).put(new Memory(stick("1024")));
        pc2.inventory().apply(5).put(hdd2);
        if (i < peerDiskDirs.size()) {
          HDDManaged disk2 = new HDDManaged(Tier.Two());
          disk2.address_$eq(Option.apply("5e550000-0000-4000-8000-00000000000" + (i + 2)));
          disk2.customRealPath_$eq(Option.apply(Paths.get(peerDiskDirs.get(i)).toAbsolutePath()));
          pc2.inventory().apply(6).put(disk2);
        }
        pc2.inventory().apply(8).put(new APU(Tier.Two()));
        pc2.inventory().apply(9).put(eeprom2);
        Screen peerScreen = ws.add(new Screen(Tier.Three()));
        Keyboard keyboard3 = ws.add(new Keyboard());
        pc2.connect(peerScreen);
        peerScreen.connect(keyboard3);
        relay.connect(i == 0 ? Direction$.MODULE$.South() : Direction$.MODULE$.East(), pc2);
        peers.add(pc2.machine());
        peerScreens.add(peerScreen);
        System.out.println("[headless] peer: T3 case, 1024+1024K, boot disk " + addr2 + ", via a relay");
      }
    }

    // A robot of its own (--chip): no OS, no disk, no screen, only the chip
    // the operator burned, a wireless card and a robot to drive. Both ends get
    // a wireless card, so nothing here is a stand-in for the modem. The robot
    // says where it ended up as the run ends: that is what a keypress did.
    if (chipFile != null) {
      pc.inventory().apply(1).put(new WirelessNetworkCard.Tier2());
      Case body = ws.add(new Case(Tier.Three()));
      EEPROM chip = new EEPROM();
      try {
        chip.codeBytes_$eq(Option.apply(Files.readAllBytes(Paths.get(chipFile))));
      } catch (java.io.IOException e) {
        throw new java.io.UncheckedIOException(e);
      }
      chip.label_$eq("rc-pilot");
      chip.volatileData_$eq(chipData == null ? new byte[0]
          : chipData.getBytes(StandardCharsets.UTF_8));
      body.inventory().apply(1).put(new WirelessNetworkCard.Tier2());
      body.inventory().apply(3).put(new Memory(stick("1024")));
      body.inventory().apply(8).put(new APU(Tier.Two()));
      body.inventory().apply(9).put(chip);
      chipRobot = ws.add(new StandInRobot());
      body.connect(chipRobot);
      peers.add(body.machine());
      System.out.println("[headless] chip machine: " + chipFile + ", robot "
          + chipRobot.node().address() + ", wireless on both ends");
    }

    machine = pc.machine();
    System.out.println("[headless] profile " + profile + ", RAM " + String.join("+", sticks)
        + "K, boot disk " + bootAddr);
  }

  // ── Beeps ─────────────────────────────────────────────────────────
  // A machine with no speaker in the room still beeps: Brain publishes
  // every computer.beep on its EventBus. Printed as "[beep] ..." lines, so
  // a POST fault's beep code (bios.lua: one long 400 Hz, then N short
  // 900 Hz) can be read off a headless run as it would be heard.
  static final long T0 = System.nanoTime();
  static class BeepLog extends scala.runtime.AbstractPartialFunction<Event, scala.runtime.BoxedUnit> {
    @Override public boolean isDefinedAt(Event e) {
      return e instanceof BeepEvent || e instanceof BeepPatternEvent;
    }
    @Override @SuppressWarnings("unchecked")
    public <A1 extends Event, B1> B1 applyOrElse(A1 e, scala.Function1<A1, B1> dflt) {
      if (!isDefinedAt(e)) return dflt.apply(e);
      double t = (System.nanoTime() - T0) / 1e9;
      if (e instanceof BeepEvent) {
        BeepEvent b = (BeepEvent) e;
        System.out.printf("[beep] %.1fs %dHz %dms%n", t, b.frequency(), b.duration());
      } else {
        System.out.printf("[beep] %.1fs pattern %s%n", t, ((BeepPatternEvent) e).pattern());
      }
      return (B1) scala.runtime.BoxedUnit.UNIT;
    }
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
   *   type TEXT           types TEXT; \n is Enter, \t Tab, \\ a backslash;
   *                       ${NAME} is what `grab NAME` took
   *   grab NAME REGEX     remember REGEX's first group on the screen now as
   *                       ${NAME} -- carry what one machine prints (an
   *                       address, a pairing code) to where it is typed
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
   *   eject               take the floppy out of the disk drive
   *   pullcard            take the internet card out of its slot (mid-download,
   *                       say: what is left behind when the card goes)
   *   resolution W H      resize the screen from OUTSIDE TOS: the call a GPU
   *                       makes, so the machine gets the same screen_resized
   *                       a real resize sends (another program's
   *                       setResolution, a screen block broken in-world)
   *   hostmv FROM TO      rename a file on the boot disk from OUTSIDE the
   *                       machine (paths relative to the disk's root, and
   *                       both must stay on it) -- what a person does to a
   *                       disk with the machine off, e.g. remove the kernel
   *                       to see the BIOS's K4
   *   insert NAME         put floppy NAME (a --floppy) in the drive
   *   seat N              type at and read screen N from here on (--seats 2)
   *   machine N           type at and read machine N's screen (--peer-boot;
   *                       machine 1 is seat 1)
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
    Map<String, String> vars = new HashMap<>();   // `grab`
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
      // Finish typing before the next step -- at the same 20 TPS as
      // everything else. The machine's clock is world TICKS (Machine.upTime
      // is ticks / 20), so a `continue` that skipped the sleep below ran a
      // typed command's ticks back to back: machine time raced ahead of
      // the stopwatch, about 1.1 s for a 22-character command, and any
      // "since mark" across typing came out short by that much.
      if (!input.isEmpty()) { Thread.sleep(50); continue; }

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
          String text = expand(line.length() > 5 ? line.substring(5) : "", vars);
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
          String text = expand(line.length() > 6 ? line.substring(6) : "", vars);
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
        case "hostmv": {
          String[] a = line.split("\\s+");
          if (a.length != 3) { failure = "hostmv takes FROM TO"; break; }
          Path root = bootPath.normalize();
          Path from = root.resolve(a[1].replaceFirst("^/+", "")).normalize();
          Path to = root.resolve(a[2].replaceFirst("^/+", "")).normalize();
          if (!from.startsWith(root) || !to.startsWith(root)) { failure = "hostmv: paths must stay on the boot disk"; break; }
          try {
            Files.move(from, to);
          } catch (Exception ex) {
            failure = "hostmv: " + ex;
            break;
          }
          done = true;
          break;
        }
        case "pullcard":
          if (pcCase == null || pcCase.inventory().apply(2).isEmpty()) {
            failure = "pullcard: no internet card (run with --internet)"; break;
          }
          pcCase.inventory().apply(2).remove();
          done = true;
          break;
        case "resolution": {
          String[] a = line.split("\\s+");
          if (a.length != 3) { failure = "resolution takes W H"; break; }
          try {
            screen.setResolution(Integer.parseInt(a[1]), Integer.parseInt(a[2]));
          } catch (Exception ex) {
            failure = "resolution: " + ex.getMessage();   // past the screen's maximum
            break;
          }
          done = true;
          break;
        }
        case "grab": {
          if (w.length < 3) { failure = "grab takes NAME REGEX"; break; }
          java.util.regex.Matcher gm = Pattern.compile(w[2], Pattern.MULTILINE).matcher(screenText(screen));
          // The value kept is capture group 1. A pattern without one used to
          // fail as "nothing on the screen matches", with the text plainly
          // on the screen: say which it is.
          if (gm.groupCount() < 1) {
            failure = "grab " + w[1] + ": " + w[2] + " has no (capture group); grab keeps group 1";
            break;
          }
          if (!gm.find() || gm.group(1) == null) {
            failure = "grab " + w[1] + ": nothing on the screen matches " + w[2];
            break;
          }
          vars.put(w[1], gm.group(1));
          note = " (" + w[1] + " = " + gm.group(1) + ")";
          done = true;
          break;
        }
        case "machine": {
          int n = w.length > 1 ? Integer.parseInt(w[1]) : 0;
          if (n == 1) screen = screens.get(0);
          else if (n >= 2 && n - 2 < peerScreens.size()) screen = peerScreens.get(n - 2);
          else { failure = "machine: no machine " + n + (peerScreens.isEmpty() ? " (needs --peer-boot)" : ""); break; }
          done = true;
          break;
        }
        case "seat": {
          int n = w.length > 1 ? Integer.parseInt(w[1]) : 0;
          if (n < 1 || n > screens.size()) { failure = "seat: no screen " + n + " (--seats " + screens.size() + ")"; break; }
          screen = screens.get(n - 1);
          done = true;
          break;
        }
        case "eject":
          if (floppyDrive == null) { failure = "eject: no --floppy, so no disk drive"; break; }
          floppyDrive.inventory().apply(0).remove();
          done = true;
          break;
        case "insert": {
          if (floppyDrive == null) { failure = "insert: no --floppy, so no disk drive"; break; }
          FloppyManaged f = w.length > 1 ? floppies.get(w[1]) : null;
          if (f == null) { failure = "insert: no --floppy named " + (w.length > 1 ? w[1] : "(none)"); break; }
          if (floppyDrive.inventory().apply(0).nonEmpty()) { failure = "insert: the drive is not empty (eject first)"; break; }
          floppyDrive.inventory().apply(0).put(f);
          done = true;
          break;
        }
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
          + " [--disk-address UUID] [--internet] [--tape] [--seats 1|2] [--peer-boot DIR]"
          + " [--floppy NAME=DIR]... [--floppy-in NAME]"
          + " [--script FILE] [--trace]");
      System.exit(64);
    }
    Path bootDir = Paths.get(boot).toAbsolutePath();
    bootPath = bootDir;
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
    int seats = Integer.parseInt(opt(args, "--seats", "1"));
    withTape = flag(args, "--tape");
    readOnlyBoot = flag(args, "--readonly-boot");
    rawDrive = flag(args, "--raw-drive");
    withGeolyzer = flag(args, "--geolyzer");
    withRobot = flag(args, "--robot");
    withChest = flag(args, "--robot-chest");
    withRubbish = flag(args, "--robot-rubbish");
    withTransposer = flag(args, "--transposer");
    chipFile = opt(args, "--chip", null);
    chipData = opt(args, "--chip-data", null);
    if (opt(args, "--disk2", null) != null) {
      disk2Dir = Paths.get(opt(args, "--disk2", null)).toAbsolutePath();
      disk2Address = opt(args, "--disk2-address", null);
      disk2Tier = opt(args, "--disk2-tier", "2");
    }
    peerDiskDirs = opts(args, "--peer-disk");
    if (seats != 1 && seats != 2) {
      System.err.println("--seats is 1 or 2");
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
    EventBus.subscribe(new BeepLog());
    build(profile, bootDir, diskDir, bios, flag(args, "--internet"), opt(args, "--ram", null),
        opt(args, "--boot-tier", "3"), opt(args, "--disk-address", null),
        opts(args, "--floppy"), opt(args, "--floppy-in", null), seats,
        opts(args, "--peer-boot"));
    System.out.println("[headless] power on: " + (machine.start() ? "ok" : "refused"));
    for (Machine peer : peers) System.out.println("[headless] peer power on: " + (peer.start() ? "ok" : "refused"));

    int code = script != null ? runScript(Paths.get(script), timeout, work) : runUntilOff(timeout, work);
    if (chipRobot != null) {
      System.out.println("[headless] chip robot ended at " + chipRobot.x + "," + chipRobot.y
          + "," + chipRobot.z + ", slot " + chipRobot.selected());
    }
    if (machine.isRunning()) machine.stop();
    for (Machine peer : peers) if (peer.isRunning()) peer.stop();
    Ocelot.shutdown();
    System.exit(code);
  }
}
