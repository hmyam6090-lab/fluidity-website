import { useEffect, useState } from "react";
import {
  codeSamples,
  codeSamplesBlurb,
  demoBlurb,
  descriptionCopy,
  facts,
  features,
  galleryGroups,
  heroAssets,
  heroPitch,
  heroStats,
  heroSummary,
  highlightCards,
  links,
  sectionBackgrounds,
  sectionSeparators,
  soundtrackBlurb,
  teamMembers,
  teamPhoto,
} from "./content";

const navLinks = [
  { href: "#demo", label: "Demo" },
  { href: "#factsheet", label: "Fact Sheet" },
  { href: "#description", label: "Description" },
  { href: "#images", label: "Images" },
  { href: "#music", label: "Music" },
  { href: "#code-samples", label: "Code" },
  { href: "#team", label: "Our Team" },
];

function SectionHeading({ eyebrow, title, intro, delay = 0 }) {
  return (
    <div
      className="section-heading"
      data-reveal
      style={{ "--reveal-delay": `${delay}ms` }}
    >
      <p className="section-heading__eyebrow">{eyebrow}</p>
      <h2 className="section-heading__title">{title}</h2>
      <p className="section-heading__intro">{intro}</p>
    </div>
  );
}

function SectionSeparator({ src, className = "" }) {
  return (
    <img
      className={`section-separator ${className}`.trim()}
      src={src}
      alt=""
      aria-hidden="true"
    />
  );
}

function getGalleryTileClass(groupIndex, itemIndex, total) {
  const patterns = [
    ["gallery-tile--hero", "gallery-tile--tall", "gallery-tile--wide", "gallery-tile--square"],
    ["gallery-tile--tall", "gallery-tile--hero", "gallery-tile--square", "gallery-tile--wide"],
    ["gallery-tile--hero", "gallery-tile--square", "gallery-tile--wide", "gallery-tile--tall"],
  ];

  if (total > 1 && total % 2 === 1 && itemIndex === total - 1) {
    return "gallery-tile gallery-tile--full";
  }

  const pattern = patterns[groupIndex % patterns.length];
  const variant = pattern[itemIndex % pattern.length] ?? "gallery-tile--square";

  return `gallery-tile ${variant}`;
}

function GalleryGroup({ group, index, onSelectImage }) {
  return (
    <article
      className="panel gallery-group"
      data-reveal
      style={{ "--reveal-delay": `${120 + index * 90}ms` }}
    >
      <div className="gallery-group__copy">
        <h3>{group.title}</h3>
        <p>{group.description}</p>
      </div>
      <div className="gallery-grid">
        {group.items.map((item, itemIndex) => (
          <button
            key={item.src}
            className={getGalleryTileClass(index, itemIndex, group.items.length)}
            type="button"
            onClick={() => onSelectImage(item)}
          >
            <img loading="lazy" src={item.src} alt={item.alt} />
            <span className="gallery-tile__meta">
              <strong>{item.title}</strong>
              <span>{item.caption}</span>
            </span>
          </button>
        ))}
      </div>
    </article>
  );
}

function TeamCard({ member, index }) {
  const contactProps = member.contactHref.startsWith("http")
    ? { target: "_blank", rel: "noreferrer" }
    : {};

  return (
    <article
      className="panel team-card"
      data-reveal
      style={{ "--reveal-delay": `${80 + index * 70}ms` }}
    >
      <img className="team-card__photo" src={member.image} alt={member.alt} />
      <div className="team-card__body">
        <p className="team-card__role">{member.role}</p>
        <h3>{member.name}</h3>
        <a className="button button--secondary team-card__button" href={member.contactHref} {...contactProps}>
          {member.contactLabel}
        </a>
      </div>
    </article>
  );
}

function CodeSampleCard({ sample, isActive, onSelect }) {
  return (
    <button
      className={`code-sample-card${isActive ? " is-active" : ""}`}
      type="button"
      aria-pressed={isActive}
      onClick={() => onSelect(sample.id)}
    >
      <span className="code-sample-card__category">{sample.category}</span>
      <strong className="code-sample-card__title">{sample.title}</strong>
      <span className="code-sample-card__summary">{sample.summary}</span>
      <span className="code-sample-card__meta">
        <span>{sample.fileName}</span>
        <span>{sample.lineCount} lines</span>
      </span>
    </button>
  );
}

function App() {
  const [selectedImage, setSelectedImage] = useState(null);
  const [activeCodeSampleId, setActiveCodeSampleId] = useState(codeSamples[0]?.id ?? "");
  const [scrollY, setScrollY] = useState(0);

  useEffect(() => {
    let animationFrameId = 0;

    const handleScroll = () => {
      cancelAnimationFrame(animationFrameId);
      animationFrameId = window.requestAnimationFrame(() => {
        setScrollY(window.scrollY);
      });
    };

    handleScroll();
    window.addEventListener("scroll", handleScroll, { passive: true });

    return () => {
      cancelAnimationFrame(animationFrameId);
      window.removeEventListener("scroll", handleScroll);
    };
  }, []);

  useEffect(() => {
    if (!selectedImage) {
      return undefined;
    }

    const previousOverflow = document.body.style.overflow;
    const handleKeyDown = (event) => {
      if (event.key === "Escape") {
        setSelectedImage(null);
      }
    };

    document.body.style.overflow = "hidden";
    window.addEventListener("keydown", handleKeyDown);

    return () => {
      document.body.style.overflow = previousOverflow;
      window.removeEventListener("keydown", handleKeyDown);
    };
  }, [selectedImage]);

  useEffect(() => {
    const revealElements = Array.from(document.querySelectorAll("[data-reveal]"));

    if (!revealElements.length) {
      return undefined;
    }

    if (!("IntersectionObserver" in window)) {
      revealElements.forEach((element) => {
        element.classList.add("is-visible");
      });
      return undefined;
    }

    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            observer.unobserve(entry.target);
          }
        });
      },
      {
        threshold: 0.18,
        rootMargin: "0px 0px -8% 0px",
      },
    );

    revealElements.forEach((element) => observer.observe(element));

    return () => observer.disconnect();
  }, []);

  const topCloudStyle = {
    transform: `translate3d(${scrollY * -0.04}px, ${scrollY * 0.09}px, 0)`,
  };

  const mistStyle = {
    transform: `translate3d(0, ${scrollY * 0.12}px, 0)`,
  };

  const activeCodeSample =
    codeSamples.find((sample) => sample.id === activeCodeSampleId) ?? codeSamples[0];

  return (
    <div className="site-shell">
      <a className="skip-link" href="#demo">
        Skip to demo
      </a>

      <header className="site-header">
        <a className="site-header__brand" href="#demo">
          Fluidity
        </a>
        <nav className="site-header__nav" aria-label="Site sections">
          {navLinks.map((link) => (
            <a key={link.href} href={link.href}>
              {link.label}
            </a>
          ))}
        </nav>
      </header>

      <main className="site-main">
        <section
          id="demo"
          className="section section--hero"
          style={{ "--section-background": `url(${heroAssets.background})` }}
        >
          <div className="section__overlay" />
          <SectionSeparator src={sectionSeparators.hero} className="section-separator--hero" />
          <img
            className="decor decor--hero-top"
            src={heroAssets.topClouds}
            alt=""
            aria-hidden="true"
            style={topCloudStyle}
          />
          <img
            className="decor decor--hero-mist"
            src={heroAssets.mist}
            alt=""
            aria-hidden="true"
            style={mistStyle}
          />
          <img
            className="decor decor--crystal"
            src={heroAssets.crystal}
            alt=""
            aria-hidden="true"
          />

          <div className="hero-layout section__content">
            <article
              className="panel hero-copy"
              data-reveal
              style={{ "--reveal-delay": "50ms" }}
            >
              <p className="eyebrow">Electronic Pitch Kit</p>
              <img className="hero-copy__title-art" src={heroAssets.titleArt} alt="Fluidity" />
              <h1 className="sr-only">Fluidity</h1>
              <p className="hero-copy__pitch">{heroPitch}</p>
              <div className="hero-copy__actions">
                <a className="button button--primary" href={links.demo} target="_blank" rel="noreferrer">
                  Download Free Demo
                </a>
                <a className="button button--secondary" href={links.trailerView} target="_blank" rel="noreferrer">
                  Watch Trailer
                </a>
                <a className="button button--ghost" href={links.contact}>
                  Contact Us!
                </a>
              </div>
              <p className="hero-copy__demo">{demoBlurb}</p>
              <ul className="hero-copy__stats" aria-label="Key project facts">
                {heroStats.map((stat) => (
                  <li key={stat}>{stat}</li>
                ))}
              </ul>
              <p className="hero-copy__summary">{heroSummary}</p>
            </article>

            <div className="hero-media-stack">
              <article
                className="panel media-panel"
                data-reveal
                style={{ "--reveal-delay": "140ms" }}
              >
                <div className="media-panel__frame">
                  <video
                    className="media-panel__video"
                    src={links.trailerVideo}
                    title="Fluidity trailer"
                    autoPlay
                    muted
                    playsInline
                    controls
                    preload="metadata"
                  />
                </div>
                <div className="media-panel__body">
                  <p className="eyebrow">Trailer</p>
                  <h2>Watch our Trailer!</h2>
                  <p>
                    You can jump directly into the
                    free demo build, or see the motion, environments, and state changes in our
                    preview gameplay trailer!
                  </p>
                </div>
              </article>

              <article
                className="panel snapshot-panel"
                data-reveal
                style={{ "--reveal-delay": "220ms" }}
              >
                <div className="snapshot-panel__header">
                  <div>
                    <p className="eyebrow">At A Glance</p>
                    <h2>Four full levels across the water cycle</h2>
                  </div>
                </div>
                <div className="snapshot-grid">
                  {highlightCards.map((card, index) => (
                    <button
                      key={card.title}
                      className="snapshot-card"
                      type="button"
                      data-reveal
                      style={{ "--reveal-delay": `${260 + index * 60}ms` }}
                      onClick={() => setSelectedImage(card)}
                    >
                      <img src={card.image} alt={card.alt} />
                      <span>
                        <strong>{card.title}</strong>
                        <span>{card.snapshotCaption ?? card.caption}</span>
                      </span>
                    </button>
                  ))}
                </div>
              </article>
            </div>
          </div>
        </section>

        <section
          id="factsheet"
          className="section"
          style={{ "--section-background": `url(${sectionBackgrounds.factsheet})` }}
        >
          <div className="section__overlay section__overlay--cool" />
          <SectionSeparator
            src={sectionSeparators.factsheet}
            className="section-separator--factsheet"
          />
          <img className="decor decor--snow-tree" src={heroAssets.snowTree} alt="" aria-hidden="true" />

          <div className="section__content">
            <SectionHeading
              eyebrow="Quick Facts"
              title="Fact Sheet"
              intro="The essentials for press, event partners, and anyone who needs the core project information fast."
              delay={50}
            />

            <div className="factsheet-layout">
              <div className="factsheet-grid">
                {facts.map((fact, index) => (
                  <article
                    key={fact.label}
                    className="panel fact-card"
                    data-reveal
                    style={{ "--reveal-delay": `${120 + index * 55}ms` }}
                  >
                    <p className="fact-card__label">{fact.label}</p>
                    {fact.href ? (
                      <a className="fact-card__value fact-card__value--link" href={fact.href}>
                        {fact.value}
                      </a>
                    ) : (
                      <p className="fact-card__value">{fact.value}</p>
                    )}
                  </article>
                ))}
              </div>

              <aside
                className="panel factsheet-callout"
                data-reveal
                style={{ "--reveal-delay": "220ms" }}
              >
                <p className="eyebrow">Ready To Share</p>
                <h3>Try our demo!</h3>
                <p>
                  Fluidity is developed by WaterWorks in Middletown, Connecticut. The demo is out now on itch.io, available for download on Windows and Mac. 
                  
                </p>
                <p>
                  Check out the trailer, then jump into the demo to experience the state-changing platforming firsthand.
                </p>
                <a className="button button--primary" href={links.demo} target="_blank" rel="noreferrer">
                  Open Itch.io Page
                </a>
              </aside>
            </div>
          </div>
        </section>

        <section
          id="description"
          className="section"
          style={{ "--section-background": `url(${sectionBackgrounds.description})` }}
        >
          <div className="section__overlay section__overlay--forest" />
          <SectionSeparator
            src={sectionSeparators.description}
            className="section-separator--description"
          />
          <img className="decor decor--sunflower" src={heroAssets.sunflower} alt="" aria-hidden="true" />

          <div className="section__content">
            <SectionHeading
              eyebrow="Game Overview"
              title="Description"
              intro="A deeper dive into the gameplay, narrative, and educational goals of the project for those who want to understand the experience beyond the trailer and demo."
              delay={50}
            />

            <div className="description-layout">
              <article
                className="panel feature-panel"
                data-reveal
                style={{ "--reveal-delay": "120ms" }}
              >
                <p className="eyebrow">The Experience</p>
                <p>{descriptionCopy}</p>
                
                <p>Our goal is to educate players about MS-ESS2-4 Earth's Systems through engaging and interactive gameplay. We wanted to create a difficult but doable movement-based platformer that teaches students about the workings of the water cycle
                where the difficulty will help with learning.</p>

                <p>We want the students to be immersed in our game and encourage them to learn about temperature’s effects on states of matter in water through our mechanics, cleverly using level design to teach kids specifics about the water cycle.</p>
              </article>
              <article
                className="panel feature-panel"
                data-reveal
                style={{ "--reveal-delay": "190ms" }}
              >
                <p className="eyebrow">Features</p>
                <ul className="feature-list">
                  {features.map((feature) => (
                    <li key={feature}>{feature}</li>
                  ))}
                </ul>
              </article>
            </div>
            <div className="highlight-grid">
              {highlightCards.map((card, index) => (
                <button
                  key={card.title}
                  className="panel highlight-card"
                  type="button"
                  data-reveal
                  style={{ "--reveal-delay": `${250 + index * 70}ms` }}
                  onClick={() => setSelectedImage(card)}
                >
                  <img src={card.image} alt={card.alt} />
                  <span className="highlight-card__copy">
                    <strong>{card.title}</strong>
                    <span>{card.caption}</span>
                  </span>
                </button>
              ))}
            </div>
          </div>
        </section>

        <section
          id="images"
          className="section"
          style={{ "--section-background": `url(${sectionBackgrounds.images})` }}
        >
          <div className="section__overlay section__overlay--sky" />
          <SectionSeparator src={sectionSeparators.images} className="section-separator--images" />

          <div className="section__content">
            <SectionHeading
              eyebrow="Press Assets"
              title="Images"
              intro="A tighter gallery focused on background art from the Assets folder and classroom photos of students playing the game."
              delay={50}
            />

            <div className="gallery-stack">
              {galleryGroups.map((group, index) => (
                <GalleryGroup
                  key={group.title}
                  group={group}
                  index={index}
                  onSelectImage={setSelectedImage}
                />
              ))}
            </div>
          </div>
        </section>

        <section
          id="music"
          className="section"
          style={{ "--section-background": `url(${sectionBackgrounds.music})` }}
        >
          <div className="section__overlay section__overlay--cave" />
          <SectionSeparator src={sectionSeparators.music} className="section-separator--music" />
          <img className="decor decor--cave-crystal" src={heroAssets.crystal} alt="" aria-hidden="true" />

          <div className="section__content">
            <SectionHeading
              eyebrow="Soundtrack"
              title="Music"
              intro="The project includes a full SoundCloud set, so the soundtrack can live inside the pitch kit instead of being just a text link."
              delay={50}
            />

            <div className="music-layout">
              <article
                className="panel music-copy"
                data-reveal
                style={{ "--reveal-delay": "120ms" }}
              >
                <p>{soundtrackBlurb}</p>
                <div className="music-copy__actions">
                  <a className="button button--primary" href={links.soundCloud} target="_blank" rel="noreferrer">
                    Open SoundCloud Set
                  </a>
                  <a className="button button--ghost" href={links.contact}>
                    Request More Info
                  </a>
                </div>
              </article>

              <article
                className="panel music-player"
                data-reveal
                style={{ "--reveal-delay": "190ms" }}
              >
                <iframe
                  title="Fluidity soundtrack on SoundCloud"
                  src={links.soundCloudEmbed}
                  loading="lazy"
                  allow="autoplay"
                />
              </article>
            </div>
          </div>
        </section>

        <section
          id="code-samples"
          className="section"
          style={{ "--section-background": `url(${sectionBackgrounds.codeSamples})` }}
        >
          <div className="section__overlay section__overlay--forest" />
          <SectionSeparator src={sectionSeparators.codeSamples} className="section-separator--code" />
          <img className="decor decor--dark-clouds" src={heroAssets.darkClouds} alt="" aria-hidden="true" />

          <div className="section__content">
            <SectionHeading
              eyebrow="Programming"
              title="Code Samples"
              intro={codeSamplesBlurb}
              delay={50}
            />

            <div className="code-samples-layout">
              {activeCodeSample ? (
                <article
                  className="panel code-preview"
                  data-reveal
                  style={{ "--reveal-delay": "120ms" }}
                >
                  <div className="code-preview__header">
                    <div>
                      <p className="eyebrow">{activeCodeSample.category}</p>
                      <h3>{activeCodeSample.title}</h3>
                      <p>{activeCodeSample.summary}</p>
                    </div>
                    <a
                      className="button button--primary"
                      href={activeCodeSample.downloadHref}
                      download={activeCodeSample.fileName}
                    >
                      Download Snippet
                    </a>
                  </div>

                  <div className="code-preview__meta" aria-label="Selected code sample details">
                    <span>{activeCodeSample.fileName}</span>
                    <span>GDScript</span>
                    <span>{activeCodeSample.lineCount} lines</span>
                  </div>

                  <pre className="code-preview__snippet">
                    <code>{activeCodeSample.preview}</code>
                  </pre>
                </article>
              ) : null}

              <aside
                className="panel code-sample-list"
                data-reveal
                style={{ "--reveal-delay": "190ms" }}
              >
                <div className="code-sample-list__header">
                  <p className="eyebrow">Core Scripts</p>
                  <h3>Preview a system, then download the file.</h3>
                </div>

                <div className="code-sample-list__grid">
                  {codeSamples.map((sample) => (
                    <CodeSampleCard
                      key={sample.id}
                      sample={sample}
                      isActive={sample.id === activeCodeSample?.id}
                      onSelect={setActiveCodeSampleId}
                    />
                  ))}
                </div>
              </aside>
            </div>
          </div>
        </section>

        <section
          id="team"
          className="section"
          style={{ "--section-background": `url(${sectionBackgrounds.team})` }}
        >
          <div className="section__overlay section__overlay--closing" />
          <SectionSeparator src={sectionSeparators.team} className="section-separator--team" />
          <img className="decor decor--closing-clouds" src={heroAssets.topClouds} alt="" aria-hidden="true" />

          <div className="section__content">
            <SectionHeading
              eyebrow="Credits"
              title="Our Team"
              intro="Fluidity is built by a five-person team spanning production, programming, art, and sound design."
              delay={50}
            />

            <div className="team-grid">
              {teamMembers.map((member, index) => (
                <TeamCard key={member.name} member={member} index={index} />
              ))}
            </div>

            <article
                  data-reveal
              style={{ "--reveal-delay": "180ms" }}
            >
              <img className="team-closing__photo" src={teamPhoto.src} alt={teamPhoto.alt} />
              <div className="team-closing__copy">
                <p className="eyebrow">WaterWorks</p>
                <h3>A team of tight-knit, young but passionate game developers</h3>
                <p>
                  Download our demo!
                  Watch the trailer, or reach out directly for press and event conversations.
                </p>
                <div className="team-closing__actions">
                  <a className="button button--primary" href={links.demo} target="_blank" rel="noreferrer">
                    Download The Demo
                  </a>
                  <a className="button button--secondary" href={links.trailerView} target="_blank" rel="noreferrer">
                    Open Trailer
                  </a>
                  <a className="button button--ghost" href={links.contact}>
                    Email WaterWorks
                  </a>
                </div>
              </div>
            </article>
          </div>
        </section>
      </main>

      <footer className="site-footer">
        <p>Fluidity by WaterWorks</p>
        <p>Demo available now for PC &amp; Mac</p>
      </footer>

      {selectedImage ? (
        <div
          className="lightbox"
          role="dialog"
          aria-modal="true"
          aria-label={selectedImage.title}
          onClick={() => setSelectedImage(null)}
        >
          <div className="lightbox__panel" onClick={(event) => event.stopPropagation()}>
            <button
              className="lightbox__close"
              type="button"
              onClick={() => setSelectedImage(null)}
            >
              Close
            </button>
            <img className="lightbox__image" src={selectedImage.image ?? selectedImage.src} alt={selectedImage.alt} />
            <div className="lightbox__copy">
              <h3>{selectedImage.title}</h3>
              <p>{selectedImage.caption}</p>
            </div>
          </div>
        </div>
      ) : null}
    </div>
  );
}

export default App;
