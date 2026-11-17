const contentModules = import.meta.glob("../Content/**/*.{png,jpg,jpeg}", {
  eager: true,
  import: "default",
});

const assetModules = import.meta.glob("../Assets/**/*.{png,jpg,jpeg}", {
  eager: true,
  import: "default",
});

const codeSampleSourceModules = import.meta.glob("../Content/Code_Samples/*.gd", {
  eager: true,
  query: "?raw",
  import: "default",
});

const codeSampleUrlModules = import.meta.glob("../Content/Code_Samples/*.gd", {
  eager: true,
  query: "?url",
  import: "default",
});

const imageMap = {
  ...contentModules,
  ...assetModules,
};

const codeSampleMap = Object.keys(codeSampleSourceModules).reduce((samples, path) => {
  samples[path] = {
    source: codeSampleSourceModules[path],
    url: codeSampleUrlModules[path],
  };

  return samples;
}, {});

const resolveImage = (path) => {
  const image = imageMap[path];

  if (!image) {
    throw new Error(`Missing image asset: ${path}`);
  }

  return image;
};

const resolveCodeSample = (path) => {
  const sample = codeSampleMap[path];

  if (!sample?.source || !sample?.url) {
    throw new Error(`Missing code sample asset: ${path}`);
  }

  return sample;
};

const makeCodeSample = ({ file, category, title, summary, previewLines = 18 }) => {
  const path = `../Content/Code_Samples/${file}`;
  const { source, url } = resolveCodeSample(path);
  const trimmedSource = source.trimEnd();
  const lines = trimmedSource.split("\n");
  const preview = lines.slice(0, previewLines).join("\n");

  return {
    id: file.replace(/\.gd$/, ""),
    fileName: file,
    category,
    title,
    summary,
    lineCount: lines.length,
    preview: lines.length > previewLines ? `${preview}\n# ...` : preview,
    downloadHref: url,
  };
};

const trailerId = "vgPaHUHjU-Q";
const soundCloudUrl = "https://soundcloud.com/noak-a/sets/fluidity";

export const links = {
  demo: "https://hmyam6090-lab.itch.io/fluidity",
  trailerView: `https://www.youtube.com/watch?v=${trailerId}`,
  trailerEmbed: `https://www.youtube.com/embed/${trailerId}?autoplay=1&mute=1&rel=0&playsinline=1`,
  soundCloud: soundCloudUrl,
  soundCloudEmbed: `https://w.soundcloud.com/player/?url=${encodeURIComponent(soundCloudUrl)}&color=%23126da6&auto_play=false&hide_related=false&show_comments=false&show_user=true&show_reposts=false&show_teaser=true&visual=true`,
  contact: "mailto:nkofmanadsit@gmail.com",
};

export const heroAssets = {
  titleArt: resolveImage("../Assets/Art/Title/Title_Art.png"),
  background: resolveImage("../Assets/Art/Background/main_menu_bg.png"),
  topClouds: resolveImage(
    "../Assets/Art/Decor & Foreground/clouds_foreground_variation_top.png",
  ),
  bottomClouds: resolveImage(
    "../Assets/Art/Decor & Foreground/clouds_foreground_variation_bottom.png",
  ),
  mist: resolveImage("../Assets/Art/Decor & Foreground/light_clouds_foreground.png"),
  darkClouds: resolveImage("../Assets/Art/Decor & Foreground/dark_clouds_foreground.png"),
  crystal: resolveImage("../Assets/Art/Decor & Foreground/crystal.png"),
  bush: resolveImage("../Assets/Art/Decor & Foreground/dark_bush_foreground.png"),
  lightBush: resolveImage(
    "../Assets/Art/Decor & Foreground/light_bush_foreground.png",
  ),
  ground: resolveImage("../Assets/Art/Decor & Foreground/light_ground_foreground.png"),
  purpleFlower: resolveImage(
    "../Assets/Art/Decor & Foreground/purple_flower.png",
  ),
  redFlower: resolveImage("../Assets/Art/Decor & Foreground/red_flower.png"),
  sunflower: resolveImage("../Assets/Art/Decor & Foreground/sunflower.png"),
  snowParticles: resolveImage(
    "../Assets/Art/Decor & Foreground/snow_particles.png",
  ),
  snowTree: resolveImage("../Assets/Art/Decor & Foreground/snow_tree.png"),
};

export const sectionBackgrounds = {
  factsheet: resolveImage("../Assets/Art/Background/ice_mountain.png"),
  description: resolveImage("../Assets/Art/Background/forest_background.png"),
  images: resolveImage("../Assets/Art/Background/clouds_background.png"),
  music: resolveImage("../Assets/Art/Background/ice_cave_bg.png"),
  codeSamples: resolveImage("../Assets/Art/Background/forest_background.png"),
  team: resolveImage("../Assets/Art/Background/main_menu_bg.png"),
};

export const sectionSeparators = {
  hero: resolveImage("../Assets/Art/Decor & Foreground/light_ground_foreground.png"),
  factsheet: resolveImage(
    "../Assets/Art/Decor & Foreground/clouds_foreground_variation_bottom.png",
  ),
  description: resolveImage(
    "../Assets/Art/Decor & Foreground/light_bush_foreground.png",
  ),
  images: resolveImage(
    "../Assets/Art/Decor & Foreground/clouds_foreground_variation_bottom.png",
  ),
  music: resolveImage("../Assets/Art/Decor & Foreground/dark_grass_foreground.png"),
  codeSamples: resolveImage(
    "../Assets/Art/Decor & Foreground/light_bush_foreground.png",
  ),
  team: resolveImage("../Assets/Art/Decor & Foreground/dark_bush_foreground.png"),
};

export const descriptionCopy =
  "Fluidity is a educational movement-based 2D Platformer about the water cycle wherein players are taken on a breathtaking natural journey, moving fluidly between ice, water, and water vapor depending on the temperature of their environment in order to overcome engaging challenges.";

export const heroPitch = "A educational movement-based 2D platformer about the water cycle.";

export const heroSummary =
  "Players control a water character that changes state with temperature, moving between ice, water, and vapor to overcome platforming challenges while learning how the water cycle works.";

export const demoBlurb =
  "Play the free demo on itch.io and put Fluidity's state-changing platforming at the front of the gamifying education";

export const features = [
  "4 Full Levels (Ice Cave, Snow, Runoff, Clouds)",
  "4 Full Pieces of Music",
  "Beautiful array of art evoking the majesty of the natural world",
  "Core mechanic is the ability to change between the states of matter in order to overcome different platforming challenges",
  "A litany of level-specific mechanics such as plants which absorb water but allow ice to move across them",
];

export const heroStats = [
  "Demo available now",
  "PC & Mac",
  "4 full levels",
  "Water cycle platforming",
];

export const facts = [
  { label: "Developer", value: "WaterWorks Games" },
  { label: "Based In", value: "Middletown, CT" },
  { label: "Release Date", value: "Demo Released 5/10/26" },
  { label: "Platforms", value: "PC & Mac" },
  {
    label: "Contact",
    value: "nkofmanadsit@gmail.com",
    href: "mailto:nkofmanadsit@gmail.com",
  },
];

export const highlightCards = [
  {
    title: "Ice Cave",
    caption: "One of four full levels in Fluidity's journey through the water cycle.",
    snapshotCaption: "State-shifting movement through the first icy level.",
    image: resolveImage("../Content/Images/Game_Screenshots/ice_cave_screenshot.png"),
    alt: "Fluidity gameplay screenshot showing the Ice Cave level.",
  },
  {
    title: "Snow",
    caption: "Shift states to navigate cold, momentum-driven platforming spaces.",
    snapshotCaption: "Cold, momentum-driven platforming in the snow biome.",
    image: resolveImage("../Content/Images/Game_Screenshots/snow_level_screenshot.png"),
    alt: "Fluidity gameplay screenshot showing movement through the Snow level.",
  },
  {
    title: "Runoff",
    caption: "Carry the motion of water through handcrafted environmental challenges.",
    snapshotCaption: "Handcrafted runoff routes that reward flowing movement.",
    image: resolveImage("../Content/Images/Game_Screenshots/runoff_level.png"),
    alt: "Fluidity gameplay screenshot showing the Runoff level.",
  },
  {
    title: "Clouds",
    caption: "Rise into vapor-themed spaces that complete the water cycle arc.",
    snapshotCaption: "A vapor-stage finale high in the clouds.",
    image: resolveImage("../Content/Images/Game_Screenshots/cloud_level.png"),
    alt: "Fluidity gameplay screenshot set in the Clouds level.",
  },
];

const makeGalleryItems = (folder, items) =>
  items.map((item) => ({
    ...item,
    src: resolveImage(`${folder}/${item.file}`),
  }));

export const galleryGroups = [
  {
    title: "Background Art",
    description: "These are the in-game background plates from the Assets folder. Together they show the temperature arc of the journey, from cold caves to open sky, while setting the tone for each stretch of the water cycle.",
    items: makeGalleryItems("../Assets/Art/Background", [
      {
        file: "ice_cave_bg.png",
        title: "Ice Cave Background",
        caption: "A colder, denser backdrop that gives the opening biome its sense of depth and pressure.",
        alt: "Fluidity background art showing the Ice Cave environment.",
      },
      {
        file: "ice_mountain.png",
        title: "Ice Mountain Background",
        caption: "The mountain silhouette pushes the scale outward and makes the frozen spaces feel much larger than the play area itself.",
        alt: "Fluidity background art showing the Ice Mountain environment.",
      },
      {
        file: "forest_background.png",
        title: "Forest Background",
        caption: "This warmer scene helps the middle of the game breathe, with a softer palette that sells the runoff transition.",
        alt: "Fluidity background art showing the Forest environment.",
      },
      {
        file: "main_menu_bg.png",
        title: "Main Menu Background",
        caption: "The title-screen composition is the broadest statement of the game's atmosphere: calm, airy, and slightly mystical.",
        alt: "Fluidity main menu background art.",
      },
      {
        file: "clouds_background.png",
        title: "Clouds Background",
        caption: "The final skyward backdrop leans into softness and altitude, which makes the vapor-focused ending feel light and earned.",
        alt: "Fluidity background art showing the Clouds environment.",
      },
    ]),
  },
  {
    title: "Players",
    description: "Classroom photos from students playing Fluidity, included here as proof that the project lands with the age group it is built for.",
    items: makeGalleryItems("../Content/Images/Players", [
      {
        file: "2eadc070.jpg",
        title: "MacDonough Playtest 01",
        caption: "Second Grade Students at MacDonough Primary School completely immersed in our game.",
        alt: "Second grade students at MacDonough Primary School playing Fluidity.",
      },
      {
        file: "c0ea3a0f.jpg",
        title: "MacDonough Playtest 02",
        caption: "Another second grade playtest moment at MacDonough, with students huddled in and reacting together as they work through the level.",
        alt: "Second grade students at MacDonough Primary School reacting to Fluidity during a classroom playtest.",
      },
      {
        file: "f1adeb97.jpg",
        title: "MacDonough Playtest 03",
        caption: "A third grade classroom session where students quickly pick up the temperature mechanics and talk through solutions while they play.",
        alt: "Third grade students playing Fluidity during a classroom session.",
      },
    ]),
  },
];

export const soundtrackBlurb =
  "4 Full Pieces of Music support Fluidity's natural journey across ice, water, and water vapor. The full set is available on SoundCloud.";

export const codeSamplesBlurb =
  "A compact look at the core GDScript systems behind Fluidity. Pick a script to preview the real source and download the snippet for closer inspection.";

export const codeSamples = [
  makeCodeSample({
    file: "player_state.gd",
    category: "State Controller",
    title: "Player State",
    summary:
      "The central temperature and form-switching controller that manages transitions, death handling, and room-driven behavior.",
    previewLines: 24,
  }),
  makeCodeSample({
    file: "water_softbody.gd",
    category: "Movement System",
    title: "Water Softbody",
    summary:
      "The water-form controller focuses on softbody movement, shared zone checks, and the feel of flow through the level.",
    previewLines: 22,
  }),
  makeCodeSample({
    file: "vapor_softbody.gd",
    category: "Movement System",
    title: "Vapor Softbody",
    summary:
      "The vapor form trades ground movement for lift, steering, and lightweight trail feedback built for the final phase of the cycle.",
    previewLines: 20,
  }),
  makeCodeSample({
    file: "ice.gd",
    category: "Movement System",
    title: "Ice Controller",
    summary:
      "The ice-form controller handles grounded platforming, jump forgiveness, and shatter-pressure feedback in colder spaces.",
    previewLines: 20,
  }),
  makeCodeSample({
    file: "room_state.gd",
    category: "Level Runtime",
    title: "Room State",
    summary:
      "Each level registers room bounds, base temperatures, and music context changes so scenes stay data-driven instead of bespoke.",
    previewLines: 20,
  }),
  makeCodeSample({
    file: "music_manager.gd",
    category: "Audio System",
    title: "Music Manager",
    summary:
      "A dual-player crossfade manager that swaps tracks, preserves sync groups, and chains contexts across the soundtrack.",
    previewLines: 22,
  }),
  makeCodeSample({
    file: "sfx_manager.gd",
    category: "Audio System",
    title: "SFX Manager",
    summary:
      "A centralized one-shot sound layer with cooldowns and automatic UI wiring so sound effects stay consistent across the build.",
    previewLines: 22,
  }),
];

export const teamMembers = [
  {
    role: "Producer/Designer",
    name: "Noa Koffman-Adsit",
    image: resolveImage("../Content/OurTeam/Photo/noa_headshot.png"),
    alt: "Headshot of Noa Koffman-Adsit.",
    contactLabel: "Email Noa",
    contactHref: "mailto:nkofmanadsit@gmail.com?subject=Fluidity%20-%20Noa%20Koffman-Adsit",
  },
  {
    role: "Lead Programmer",
    name: "Quan Hoang",
    image: resolveImage("../Content/OurTeam/Photo/quan_headshot.png"),
    alt: "Headshot of Quan Hoang.",
    contactLabel: "Contact Quan",
    contactHref: "https://quanhoang.dev/",
  },
  {
    role: "Artist",
    name: "Sorielis Paulino",
    image: resolveImage("../Content/OurTeam/Photo/sorielis_headshot.png"),
    alt: "Headshot of Sorielis Paulino.",
    contactLabel: "Contact Sorielis",
    contactHref: "mailto:spaulino@wesleyan.edu?subject=Fluidity%20-%20Sorielis%20Paulino",
  },
  {
    role: "Composer/Sound Designer",
    name: "Maggie Sun",
    image: resolveImage("../Content/OurTeam/Photo/maggie_headshot.png"),
    alt: "Headshot of Maggie Sun.",
    contactLabel: "Contact Maggie",
    contactHref: "mailto:msun03@wesleyan.edu?subject=Fluidity%20-%20Maggie%20Sun",
  },
  {
    role: "Programmer/Designer",
    name: "Dalton Soper",
    image: resolveImage("../Content/OurTeam/Photo/dalton_headshot.png"),
    alt: "Headshot of Dalton Soper.",
    contactLabel: "Contact Dalton",
    contactHref: "mailto:dsoper@wesleyan.edu?subject=Fluidity%20-%20Dalton%20Soper",
  },
];

export const teamPhoto = {
  src: resolveImage("../Content/OurTeam/Photo/team_photo.jpg"),
  alt: "The Fluidity team holding artwork from the game.",
};
