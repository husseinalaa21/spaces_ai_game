# MASTER BUILD PROMPT — "AI" GAME

## 0. ROLE AND OBJECTIVE

You are building a complete mobile game called **AI** for Apple platforms, with the primary target being iPhone/iPad and distribution through the Apple App Store.

The game must feel original, extremely minimal, easy to understand immediately, but deep enough to support long-term progression, multiplayer competition, collecting, transformation, social interaction, and premium membership.

The player is ALWAYS represented as a **dot/circle**.

Do not turn the player into a human, spaceship, animal, 3D character, robot body, or traditional game avatar.

The core identity of the game is:

> You begin as a tiny dot inside a huge white space.  
> You explore, eat icon-based objects, absorb their properties, slowly transform, reach 100% forms, unlock new levels, enter Dark Space, grow larger, compete with other real players, communicate above your dot, and continue evolving while always remaining a dot.

The game should be visually simple but mechanically rich.

---

# 1. GAME NAME

**AI**

Use "AI" as the game title.

The name should feel mysterious and minimal.

Possible subtitle concepts for App Store use later:
- AI — Eat. Change. Evolve.
- AI — Become Anything.
- AI — White Space
- AI — Evolve the Dot
- AI — Explore. Absorb. Survive.

Do not hard-code a subtitle into the game title itself unless required by App Store metadata.

---

# 2. CORE DESIGN PHILOSOPHY

The game must follow these principles:

1. **The player is always a dot.**
2. The world begins visually simple.
3. Complexity comes from gameplay, not from clutter.
4. Every object the player eats should matter.
5. Transformation must happen gradually, not instantly.
6. Players should be able to look at another dot and understand something about its history, current form, size, rarity, or membership status.
7. The world should feel huge.
8. The game should support both peaceful exploration and competitive multiplayer.
9. The White Space and Dark Space must feel fundamentally different.
10. Premium membership should make players look and feel special without destroying competitive balance.
11. The game should be easy to start with one finger.
12. The game should become deeper the longer the player plays.

---

# 3. THE PLAYER

Every player starts as a small, simple dot.

Initial appearance:
- Circular.
- Small.
- Neutral dark gray or black.
- No face.
- No limbs.
- No character model.
- No excessive glow.
- No unnecessary border.
- No shadow-heavy style.

The dot represents the player completely.

The player may later gain:
- Color.
- Texture.
- Animated interior.
- Ring.
- Trail.
- Particles.
- Small icon badge.
- Temporary effects.
- Premium cosmetic material.
- Size changes.

But the silhouette must remain a circle/dot.

---

# 4. GAME WORLD STRUCTURE

The game is divided into major spaces.

## LEVEL / WORLD 1 — WHITE SPACE

White Space is the beginning.

Visual style:
- Pure or near-pure white background.
- Very large/open map.
- Minimal interface.
- The player's dot is clearly visible.
- Collectible objects are smaller dots containing icons.
- Other players may also appear as dots.
- Distant objects may fade slightly based on distance.
- No unnecessary decorative environment.

White Space is the world of:
- Discovery.
- Learning.
- Collection.
- Transformation.
- Experimentation.
- Preparation.
- Unlocking forms.

The player travels through White Space and eats small collectible dots.

Each collectible dot contains an icon representing a thing, material, object, emotion, animal, technology, food, force, or idea.

Examples:
- Banana
- Rock
- Fire
- Water
- Blood
- Brain
- Battery
- Star
- Robot
- Rabbit
- Ghost
- Diamond

Eating one does NOT instantly change the player.

It contributes a percentage to a transformation.

---

# 5. TRANSFORMATION SYSTEM

This is one of the most important systems in the entire game.

## Basic rule

When a player eats a collectible, they slowly become more like that collectible.

Example:

The player eats a Banana collectible.

Display:
- Banana: 7%

Player eats another Banana:
- Banana: 14%

Again:
- Banana: 22%

Continue:
- Banana: 55%
- Banana: 82%
- Banana: 100%

At 100%, the player has completed the Banana form.

## Visual transformation

The player's dot should visibly change in real time as the percentage changes.

Example:
- 0% Banana: normal dark dot.
- 10% Banana: tiny yellow region/tint.
- 25% Banana: subtle yellow quarter influence.
- 50% Banana: roughly half of the dot appears yellow or banana-textured.
- 75% Banana: mostly yellow.
- 100% Banana: full Banana form.

The player is still a dot.

Do NOT make the player literally turn into a banana.

Use:
- Color.
- Texture.
- Small icon indication.
- Animated pattern.
- Edge effect.
- Particle effect.

The shape remains circular.

---

# 6. MIXED TRANSFORMATIONS

The player can absorb multiple different things.

Example:
- Banana 60%
- Rock 30%
- Fire 10%

The visual system should blend influences in a clean way.

Possible behavior:
- Main/base color determined by highest percentage.
- Secondary material appears as sectors, gradients, internal particles, or edge effects.
- The top two or three active transformations are visible.
- Very small percentages can be displayed in the details panel but not necessarily visualized heavily.

Example:

Player has:
- Electricity 70%
- Rock 30%

This could create:
- Gray/heavy dot body.
- Yellow electric pulse around the edge.
- Movement speed increased by Electricity.
- Slight weight/defense increased by Rock.

The system should support hybrid builds.

---

# 7. COMPLETING A FORM

When a material reaches 100%, unlock that form in the player's collection.

Example:
**Rock — 100% Complete**

Reward:
- Rock form permanently added to Collection.
- Rock ability unlocked.
- Rock badge/icon unlocked.
- Player can equip the completed Rock form later if game balance allows.
- Progress toward higher-level access increases.

Completing forms should feel satisfying.

Use a short but clean completion animation:
- Pulse.
- Small burst.
- Icon expands briefly.
- Text: "FORM COMPLETE".
- Avoid excessive confetti.

---

# 8. COLLECTIBLE ICON SYSTEM

The game should support a large icon library.

Collectibles appear as:
- Small circle/dot.
- Icon centered inside.
- Category color or icon-specific color.
- Slight animation if rare.
- No square cards floating in the world.

Each collectible needs data fields such as:

- id
- name
- icon
- category
- rarity
- primaryColor
- secondaryColor
- absorptionValue
- statEffects
- activeAbility
- passiveAbility
- transformationVisual
- spawnWeight
- allowedWorlds
- premiumVariant
- description

---

# 9. ICON CATEGORIES

Create a scalable content system so more icons can be added without rewriting the game.

## FOOD

Examples:
- 🍎 Apple
- 🍌 Banana
- 🍇 Grapes
- 🍉 Watermelon
- 🍓 Strawberry
- 🍒 Cherry
- 🍑 Peach
- 🍍 Pineapple
- 🥥 Coconut
- 🥝 Kiwi
- 🍋 Lemon
- 🍊 Orange
- 🥭 Mango
- 🍐 Pear
- 🫐 Blueberries
- 🍈 Melon
- 🌽 Corn
- 🥕 Carrot
- 🍅 Tomato
- 🥔 Potato
- 🧄 Garlic
- 🧅 Onion
- 🥦 Broccoli
- 🥬 Lettuce
- 🥒 Cucumber
- 🌶️ Chili
- 🫑 Pepper
- 🍄 Mushroom
- 🥜 Peanut
- 🌰 Chestnut
- 🍞 Bread
- 🥐 Croissant
- 🧀 Cheese
- 🍗 Chicken
- 🍖 Meat
- 🍔 Burger
- 🍕 Pizza
- 🌭 Hot Dog
- 🥪 Sandwich
- 🌮 Taco
- 🌯 Burrito
- 🍜 Noodles
- 🍝 Pasta
- 🍣 Sushi
- 🍤 Shrimp
- 🍦 Ice Cream
- 🍩 Donut
- 🍪 Cookie
- 🎂 Cake
- 🧁 Cupcake
- 🍫 Chocolate
- 🍬 Candy
- 🍭 Lollipop
- 🍯 Honey
- 🥛 Milk
- ☕ Coffee
- 🧃 Juice
- 🧋 Boba
- 🥤 Soda

Possible gameplay behaviors:
- Banana: slippery/unpredictable movement.
- Coffee: temporary speed boost.
- Honey: sticky slowing field.
- Chili: heat/fire boost.
- Ice Cream: cooling/freezing effect.
- Pizza: growth bonus.
- Apple: basic health recovery.
- Mushroom: random temporary mutation.

---

## NATURE / EARTH

Examples:
- 🪨 Rock
- ⛰️ Mountain
- 🪵 Wood
- 🌲 Pine Tree
- 🌳 Tree
- 🌴 Palm Tree
- 🌵 Cactus
- 🌿 Herb
- ☘️ Clover
- 🍀 Four-Leaf Clover
- 🌱 Seedling
- 🌾 Plant
- 🍁 Leaf
- 🍂 Fallen Leaf
- 🍃 Wind Leaf
- 🌸 Flower
- 🌼 Blossom
- 🌺 Hibiscus
- 🌻 Sunflower
- 🌷 Tulip
- 🌹 Rose
- 🪷 Lotus
- 🌊 Wave
- 💧 Water
- 🧊 Ice
- ❄️ Snow
- ☁️ Cloud
- 🌪️ Tornado
- 🔥 Fire
- ⚡ Lightning
- ☀️ Sun
- 🌙 Moon
- ⭐ Star
- 🌟 Glowing Star
- 💫 Spark
- 🌈 Rainbow
- 🪐 Planet
- 🌍 Earth
- 🌋 Volcano

Possible effects:
- Rock: defense / weight.
- Cactus: touch damage.
- Water: smooth movement.
- Fire: damage aura.
- Ice: slow enemies.
- Tornado: spin/dash.
- Rainbow: mixed/random effects.
- Moon: stealth.
- Sun: strong pulse.
- Clover: luck increase.
- Volcano: rare burst power.

---

## BODY / BIOLOGICAL

Examples:
- 🩸 Blood
- 🫀 Heart
- 🧠 Brain
- 🦴 Bone
- 👁️ Eye
- 👂 Ear
- 👃 Nose
- 👄 Mouth
- 🫁 Lungs
- 🦷 Tooth
- 👅 Tongue
- 💪 Muscle
- 🧬 DNA
- 🦠 Microbe
- 🧫 Petri Dish
- 💉 Syringe
- 💊 Pill
- 🩹 Bandage
- ❤️ Heart
- 💙 Blue Heart
- 💚 Green Heart
- 🖤 Black Heart
- 🤍 White Heart

Possible effects:
- Brain: improved scanning.
- Eye: increased visible range.
- Heart: health/regen.
- Blood: aggressive growth.
- DNA: mutation chance.
- Microbe: infection/debuff.
- Pill: recovery.
- Bandage: regeneration.
- Muscle: push strength.
- Lungs: stamina/boost duration.

---

## TECHNOLOGY / DIGITAL / AI

Examples:
- 🤖 Robot
- 💻 Laptop
- 🖥️ Computer
- 📱 Phone
- 🧠 Brain
- ⚙️ Gear
- 🔋 Battery
- 🪫 Empty Battery
- 🔌 Plug
- 💡 Light Bulb
- 🛰️ Satellite
- 📡 Antenna
- 🛜 Network
- 🧲 Magnet
- ⌛ Hourglass
- 🧬 DNA
- 🧪 Test Tube
- 🔬 Microscope
- 🎮 Game Controller
- 🕹️ Joystick
- 🧿 Orb
- 💿 Disc
- 📀 Disc
- 🔐 Lock
- 🔓 Unlock
- 🛡️ Shield
- 🧱 Block
- 📷 Camera
- 🔭 Telescope
- 🧭 Compass
- 🗺️ Map
- 📊 Chart
- 📈 Up Chart
- 📉 Down Chart

Possible effects:
- Robot: temporary helper-dot.
- Gear: faster upgrade efficiency.
- Battery: larger energy capacity.
- Antenna: detect players/objects farther away.
- Network: communication bonus.
- Magnet: pull collectibles toward player.
- Lock: temporary protection.
- Unlock: opens restricted objects/portals.
- Compass: objective guidance.
- Telescope: extreme detection range.
- Controller: ability cooldown improvement.

---

## SPACE

Examples:
- 🚀 Rocket
- 🛸 UFO
- 🌍 Earth
- 🌕 Moon
- ☀️ Sun
- ⭐ Star
- 🌟 Glowing Star
- 💫 Spark
- ☄️ Comet
- 🪐 Planet
- 🌌 Galaxy
- 🛰️ Satellite
- 👨‍🚀 Astronaut
- 🔭 Telescope
- 🧭 Compass

Possible effects:
- Rocket: strong speed burst.
- UFO: teleport.
- Comet: damaging dash.
- Planet: gravity pull.
- Galaxy: rare transformation.
- Satellite: map detection.
- Moon: stealth.
- Sun: illumination/damage aura.

---

## EMOTIONS / FACES

Examples:
- 😀
- 😂
- 😭
- 😡
- 😎
- 🥶
- 🥵
- 😴
- 🤯
- 😈
- 👻
- 🤡
- 🫠
- 😍
- 😱
- 🤢
- 🥳
- 🤖
- 👽
- 💀

Possible effects:
- Cool: style/speed.
- Angry: aggression.
- Crying: water trail.
- Frozen: freeze aura.
- Hot: heat aura.
- Sleeping: slow but healing.
- Mind-blown: burst.
- Ghost: temporary transparency/phase.
- Skull: dangerous damage state.
- Alien: strange/random ability.

---

## ANIMALS

Examples:
- 🐢 Turtle
- 🐇 Rabbit
- 🐍 Snake
- 🦅 Eagle
- 🐟 Fish
- 🦈 Shark
- 🐝 Bee
- 🕷️ Spider
- 🦋 Butterfly
- 🐺 Wolf
- 🦁 Lion
- 🐘 Elephant
- 🐉 Dragon
- 🐙 Octopus
- 🦊 Fox
- 🐬 Dolphin
- 🦄 Unicorn

Possible effects:
- Turtle: defense.
- Rabbit: speed.
- Snake: trail attack.
- Eagle: vision.
- Bee: swarm helper-dots.
- Spider: slowing web-zone.
- Elephant: high mass.
- Dragon: rare fire effect.
- Octopus: multi-directional pulse.
- Fox: stealth/misdirection.

---

## OBJECTS / RANDOM

Examples:
- 🔑 Key
- 🚪 Door
- 📦 Box
- 🎁 Gift
- 🪙 Coin
- 🧸 Teddy Bear
- 🕯️ Candle
- 🧼 Soap
- 🪞 Mirror
- ⌚ Watch
- ⏰ Alarm
- 🧯 Extinguisher
- 🛒 Cart
- 📌 Pin
- ✂️ Scissors
- 📎 Paperclip
- 🪄 Wand
- 🧷 Safety Pin
- 🪢 Knot
- 🪤 Trap
- 🧱 Brick
- 🧲 Magnet
- 💎 Diamond
- 🧨 Firecracker
- 🎈 Balloon
- 🪂 Parachute

Possible effects:
- Key: unlock.
- Gift: random reward.
- Mirror: reflect.
- Watch: time-related cooldown effect.
- Trap: deploy obstacle.
- Brick: defense/mass.
- Magnet: attraction.
- Diamond: rare value.
- Balloon: light/floaty movement.

---

# 10. RARITY SYSTEM

Each collectible has a rarity.

Recommended tiers:

1. Common
2. Uncommon
3. Rare
4. Epic
5. Legendary
6. Mythic / AI Core

Visual treatment should remain subtle.

Do not create giant loot-box style animations for every item.

Example:
- Common: normal icon dot.
- Uncommon: slight ring.
- Rare: light animation.
- Epic: animated edge.
- Legendary: unique particle.
- Mythic: world event or special spawn behavior.

Rarity should affect:
- Spawn rate.
- Absorption percentage.
- Potential power.
- Collection value.
- Achievement value.

---

# 11. ICON FAMILY SYSTEM

Icons can also belong to broader color/behavior families.

## Yellow / Energy family
Examples:
- Banana
- Sun
- Lightning
- Yellow Heart

Themes:
- Speed.
- Energy.
- Brightness.

## Blue / Flow family
Examples:
- Water
- Ice
- Wave
- Blue Heart

Themes:
- Flow.
- Smoothness.
- Slow/freeze.

## Red / Life / Danger family
Examples:
- Blood
- Fire
- Red Heart
- Strawberry
- Rose

Themes:
- Aggression.
- Heat.
- Life.
- Damage.

## Green / Nature family
Examples:
- Leaf
- Green Apple
- Cucumber
- Turtle
- Green Heart

Themes:
- Healing.
- Stability.
- Nature.
- Defense.

## Black / Void family
Examples:
- Skull
- Black Heart
- Moon
- Spider
- Ghost

Themes:
- Stealth.
- Fear.
- Darkness.
- Special risk/reward.

## Purple / Rare family
Examples:
- Diamond
- Grapes
- Crystal Ball
- Planet
- Galaxy

Themes:
- Rare.
- Magical.
- High value.
- Unpredictable.

---

# 12. PLAYER STATS

Keep stats understandable.

Possible core stats:
- Size
- Speed
- Defense
- Energy
- Vision
- Magnetism
- Growth Rate
- Ability Power
- Cooldown
- Luck
- Regeneration

Do not show all stats permanently on screen.

Use a clean player detail/progression screen.

---

# 13. ABILITY SYSTEM

Completed forms can unlock active or passive abilities.

Examples:

## Banana
Passive:
- More slippery turning.
- Faster direction switching.

Active:
- Short unpredictable dash.

## Rock
Passive:
- Increased resistance.
- Slightly slower.

Active:
- Harden temporarily.

## Fire
Passive:
- Damage aura.

Active:
- Fire pulse.

## Ice
Passive:
- Nearby smaller collectibles slow slightly.

Active:
- Freeze pulse.

## Electricity
Passive:
- Movement speed increase.

Active:
- Lightning dash.

## Water
Passive:
- Smooth acceleration.

Active:
- Flow through a temporary obstacle or slow-field.

## Brain
Passive:
- Improved information.

Active:
- Scan nearby objects.

## Eye
Passive:
- Increased vision.

Active:
- Reveal hidden objects.

## Magnet
Passive:
- Small collectibles drift toward player.

Active:
- Strong magnetic pull.

## Ghost
Passive:
- Slight transparency.

Active:
- Temporary phase/escape.

## Rocket
Passive:
- High acceleration.

Active:
- High-speed burst.

## Shield
Passive:
- Increased defense.

Active:
- Temporary protective shell.

Balance all abilities carefully.

No ability should guarantee victory.

---

# 14. WHITE SPACE OBJECTIVES

White Space needs goals so it does not become an empty movement simulator.

Objectives can include:

- Find a specific icon.
- Complete a form.
- Reach a location.
- Collect 10 objects from one family.
- Create a hybrid.
- Discover a rare icon.
- Find a portal.
- Follow a moving signal.
- Complete a timed challenge.
- Survive an environmental zone.
- Encounter another player.
- Trade or communicate.
- Find an AI-controlled entity.
- Scan an unknown object.

Use lightweight missions.

---

# 15. SIGNAL EVENTS

Add dynamic events called **Signals**.

Example UI:
**SIGNAL DETECTED**

A signal can spawn somewhere in White Space.

Possible Signal activities:
- Race to a coordinate.
- Capture a moving object.
- Defend an area for 30 seconds.
- Find the real icon among fake icons.
- Follow a pattern.
- Reach an object before time expires.
- Collect a sequence in the correct order.
- Avoid harmful dots.
- Compete against nearby players.

Signals reward:
- Rare icon.
- Intelligence points.
- Premium cosmetic fragment.
- Currency.
- Form progress.
- Portal access.
- Achievement.

---

# 16. INTELLIGENCE POINTS

Use a progression resource called **Intelligence**.

Earn Intelligence from:
- Discovering icons.
- Completing forms.
- Finding Signals.
- Completing missions.
- Exploring distance.
- Meeting players.
- Winning challenges.
- Entering new spaces.
- Completing collection groups.

Intelligence can unlock:
- More active slots.
- New travel abilities.
- New inventory/collection features.
- Advanced scanning.
- Cosmetic features.
- Access to later worlds.

Avoid making Intelligence simply another pay-to-win currency.

---

# 17. UNLOCKING DARK SPACE

White Space is the evolution stage.

Dark Space should not be available immediately.

Possible requirements:
- Complete several forms.
- Reach a minimum Intelligence level.
- Find a Dark Portal.
- Complete a major White Space objective.

Example:
Requirements:
- Complete 5 forms.
- Reach Intelligence Level 10.
- Complete first Signal chain.

Then:
**DARK SPACE UNLOCKED**

The player discovers/enters a portal.

Transition:
White screen → dim → black.

---

# 18. DARK SPACE

Dark Space is the competitive multiplayer world.

Visual style:
- Black/dark background.
- Dots remain highly visible.
- Small collectible dots appear in blue, pink, and other bright colors.
- Player transformations still influence appearance.
- Premium forms should stand out clearly without obscuring gameplay.

Dark Space core loop:

1. Move.
2. Eat small neutral dots.
3. Grow larger.
4. Avoid larger players.
5. Eat smaller players.
6. Use transformation abilities intelligently.
7. Communicate.
8. Survive.
9. Climb leaderboard.
10. Continue collecting/earning rewards.

---

# 19. SIZE-BASED MULTIPLAYER

Core rule:

**Larger dots can eat smaller dots.**

But size must not be the only factor.

Use abilities and form properties to create strategy.

Example:
- Large Rock player: strong but slow.
- Small Electricity player: can escape.
- Ice player: can slow pursuer.
- Ghost player: temporary phase.
- Magnet player: grows faster from nearby collectibles.
- Fire player: dangerous at close distance.

Eating another player can reward:
- Growth.
- Intelligence.
- Temporary energy.
- Small amount of collection progress.
- Leaderboard score.

Do not make death too punishing.

---

# 20. DARK SPACE NEUTRAL DOTS

The Dark Space map constantly spawns small edible dots.

Examples:
- Blue dots.
- Pink dots.
- Purple dots.
- Yellow dots.
- Rare glowing dots.

These increase size.

Different colors can have slight differences:
- Blue: standard growth.
- Pink: slightly more growth but rarer.
- Yellow: energy.
- Purple: ability charge.
- White: Intelligence fragment.
- Gold: premium-related cosmetic fragment or event item.

Keep the system simple enough to understand during fast gameplay.

---

# 21. DEATH / DEFEAT

If a player is eaten:

Do not wipe all progress.

The player keeps:
- Completed forms.
- Collection.
- Premium cosmetics.
- Intelligence level.
- Achievements.
- Account progression.

They may lose:
- Current Dark Space size.
- Temporary power.
- Current match streak.
- Temporary collected energy.

Respawn with a reasonable minimum size.

This prevents rage-quitting.

---

# 22. ONLINE MULTIPLAYER

The main game should be online-first.

Requirements:
- Real-time player movement.
- Multiple players per world/server/room.
- Server-authoritative position validation where possible.
- Anti-cheat considerations.
- Reconnection support.
- Latency smoothing/interpolation.
- Efficient bandwidth usage.
- Nearby-player prioritization.
- Graceful handling of disconnects.

Do not require thousands of players in one room at launch.

Recommended initial target:
- 20–50 players per Dark Space world/room.
- Scale later.

White Space can use:
- Shared instances.
- Smaller groups.
- AI-controlled dots if needed to keep the world feeling alive.

---

# 23. AI-CONTROLLED DOTS

Not every dot needs to be human.

Add AI-controlled dots.

They should obey the same visual rule:
- Always dots.

Possible types:
- Wanderers.
- Collectors.
- Predators.
- Cowards.
- Traders.
- Signal guides.
- Rare mysterious entities.

They can:
- Move.
- Collect.
- Avoid threats.
- Chase weaker players.
- Send limited text.
- Offer events.
- Drop rare items.

Do not clearly label every AI dot immediately.

Mystery is useful.

---

# 24. CHAT ABOVE DOTS

Players can type short messages.

The message appears above their dot.

Example:

    hello
      ●

Requirements:
- Short character limit.
- Message disappears after around 5–10 seconds.
- Avoid permanent chat clutter.
- Spam protection.
- Rate limiting.
- Mute/block/report.
- Basic moderation.
- Profanity/filtering system if appropriate.
- Do not cover the player during gameplay.

Quick messages:
- Hi
- Follow me
- Run
- Help
- Fight?
- Friendly
- Don’t eat me
- Come here
- LOL

Quick reactions:
- ❤️
- 😂
- 😡
- 👋
- 🔥
- 👑
- ⚡
- 👻

---

# 25. SOCIAL FEATURES

Possible social features:
- Username.
- Optional display name.
- Friend/follow system.
- Recent players.
- Invite friend.
- Party system later.
- Block.
- Report.
- Mute.

Do not overwhelm MVP.

For first release:
- Username.
- Short dot message.
- Recent players.
- Block/report.

---

# 26. USERNAME DISPLAY

A player can optionally display:
- Name above dot.
- Name only when tapped.
- Name only within close range.

Recommended:
- Keep default gameplay visually clean.
- Show names only when nearby, tapped, or during interaction.
- Chat text appears above name/dot.

---

# 27. PREMIUM MEMBERSHIP

Add a paid membership.

Potential name:
- AI+
- AI Premium

Recommended default:
**AI+**

Premium should focus heavily on:
- Cosmetics.
- Status.
- Customization.
- Collection.
- Convenience.

Avoid direct permanent combat superiority.

Do not make AI+ automatically stronger than free players.

---

# 28. PREMIUM DOTS

AI+ members can unlock special dot materials.

Examples:

- Gold Dot
- Diamond Dot
- Black Gold Dot
- Platinum Dot
- Galaxy Dot
- Lava Dot
- Electric Dot
- Neon Dot
- Glass Dot
- Pearl Dot
- Chrome Dot
- Rainbow Dot
- Void Dot
- Sun Dot
- Moon Dot
- AI Core Dot
- Hologram Dot
- Fire Gold Dot
- Frozen Diamond Dot
- Royal Dot

All remain circular dots.

---

# 29. PREMIUM DOT VISUALS

## Gold Dot
- Metallic gold.
- Slight moving reflection.
- No excessive glow.

## Diamond Dot
- Crystal-like internal facets.
- Clean reflection.

## Black Gold
- Deep black center.
- Thin moving gold edge/ring.

## Galaxy
- Tiny moving stars inside.
- Very subtle rotation.

## Lava
- Dark base with slow glowing cracks.

## Electric
- Small edge lightning effect.

## Glass
- Transparent/refractive appearance.

## Chrome
- Metallic moving reflection.

## Void
- Very dark center.
- Slight light-distortion appearance.

## AI Core
- Futuristic internal moving geometry.
- Minimal, intelligent look.

---

# 30. PREMIUM TRANSFORMATION VARIANTS

Premium users can unlock upgraded visual versions of normal forms.

Examples:

Normal:
- Banana
- Rock
- Fire
- Ice
- Blood

Premium visual variants:
- Golden Banana
- Obsidian Rock
- Golden Fire
- Diamond Ice
- Royal Blood
- Galaxy Water
- Chrome Robot
- Neon Electricity
- Void Ghost

Important:
These should primarily be cosmetic.

Do not make Golden Banana automatically stronger than Banana.

---

# 31. PREMIUM TRAILS

AI+ members can equip movement trails.

Examples:
- Gold particles.
- Stars.
- Electricity.
- Fire.
- Snow.
- Pixels.
- Hearts.
- Rainbow.
- Galaxy dust.
- Tiny dots.
- Digital code-like particles.

Trail requirements:
- Short.
- Lightweight.
- No visual obstruction.
- Performance-friendly.
- Adjustable/off option.

---

# 32. PREMIUM RINGS

Premium rings appear around the dot.

Examples:
- Gold Ring
- Diamond Ring
- Fire Ring
- Electric Ring
- Galaxy Ring
- Royal Ring
- Void Ring
- Neon Ring

The dot remains central.

Ring should not change collision size.

---

# 33. PREMIUM CHAT STYLE

Premium member chat can have:
- Small gold accent.
- Premium symbol.
- Optional tiny crown.
- Special text animation.
- Premium reaction effects.

Do not make it unreadable.

Do not imitate official verification marks if that could confuse users.

Use a unique membership mark.

---

# 34. PREMIUM EMOTES

AI+ users can trigger short effects around the dot.

Examples:
- ❤️ hearts orbit briefly.
- 😂 emoji floats upward.
- 🔥 quick flame ring.
- 👑 crown appears briefly.
- ⚡ lightning burst.
- 👻 ghost fade.
- ✨ sparkles.

These are visual only.

Cooldown them to prevent spam.

---

# 35. PREMIUM CUSTOM DOT BUILDER

Long-term feature:

AI+ members can combine:
- Base material.
- Ring.
- Trail.
- Icon.
- Particle style.
- Animation style.

Example:
- Base: Black.
- Ring: Gold.
- Trail: Electricity.
- Icon: Crown.
- Particle: Stars.

Still a dot.

---

# 36. PREMIUM COLLECTION PROGRESSION

Do not simply give every cosmetic instantly when subscribing.

Give members exclusive progression.

Example:
- AI+ Level 1: Gold Dot.
- AI+ Level 2: Gold Trail.
- AI+ Level 3: Diamond Dot.
- AI+ Level 4: Premium Chat Effect.
- AI+ Level 5: Galaxy Dot.
- AI+ Level 10: Black Gold.
- AI+ Level 20: AI Core.
- AI+ Level 30: Legendary Void Gold.

AI+ XP can come from:
- Playing.
- Completing forms.
- Daily challenges.
- Signal events.
- Dark Space survival.

---

# 37. PREMIUM EXCLUSIVE COLLECTIBLES

Add rare collectibles that only grant premium cosmetic progression.

Example:
**GOLD CORE**

AI+ player collects:
- Gold Core 5%
- Gold Core 17%
- Gold Core 44%
- Gold Core 82%
- Gold Core 100%

Reward:
- Gold Dot cosmetic unlock.

Important:
If a free player encounters a Gold Core:
- It can be visible.
- Explain that it is an AI+ cosmetic collectible.
- Do not aggressively interrupt gameplay with purchase prompts.

---

# 38. MONETIZATION PRINCIPLES

Monetization should never make the game feel unfair.

Preferred paid items:
- Membership.
- Dot skins/materials.
- Rings.
- Trails.
- Chat styles.
- Emotes.
- Cosmetic transformation variants.
- Collection display.
- Premium progression track.

Avoid:
- Buying huge permanent size advantage.
- Buying guaranteed wins.
- Buying unlimited damage.
- Paying to consume players who should be safe.
- Paywalling the basic game.

---

# 39. STORE / MEMBERSHIP SCREEN

Keep store minimal.

Sections:
- AI+
- Premium Dots
- Trails
- Rings
- Emotes
- Transformation Skins

Membership card:
- Clean.
- No fake countdown timers.
- No excessive sale banners.
- Clear billing terms.
- Clear restore purchase button.
- Clear manage subscription path.

---

# 40. APP STORE PAYMENT COMPLIANCE

For digital game content on Apple platforms:
- Use Apple's required in-app purchase/subscription mechanisms where applicable.
- Do not direct users to unsupported external payment methods inside the app for digital items.
- Keep subscription terms clear.
- Support Restore Purchases.
- Handle StoreKit purchase state correctly.
- Validate entitlements appropriately.

---

# 41. WHITE SPACE UI

Default screen should be extremely clean.

Possible HUD:
Top-left or top-center:
- Current form / dominant absorption.

Example:
**Banana 42%**

Top-right:
- Intelligence level.

Bottom-left:
- Movement control if joystick is used.

Bottom-right:
- Ability button.
- Chat button.
- Scan button if unlocked.

Avoid:
- Huge bars.
- Large opaque panels.
- Clutter.

---

# 42. MOVEMENT

Movement should feel smooth.

Possible mobile control:
Option A:
- Drag anywhere to move.

Option B:
- Invisible joystick.

Recommended:
Test both.

Requirements:
- Smooth acceleration.
- No frustrating delay.
- Touch-friendly.
- Supports quick direction changes.
- Different forms can alter handling slightly.

---

# 43. CAMERA

The camera should:
- Follow player smoothly.
- Zoom out slightly as size increases.
- Never make the player impossible to see.
- Allow limited pinch zoom if useful.
- Avoid motion sickness.

In White Space:
- Wider exploration feeling.

In Dark Space:
- Enough awareness to avoid larger players.

---

# 44. COLLISION / EATING

For collectibles:
- Player overlaps collectible.
- Server validates.
- Collectible disappears.
- Absorption percentage increases.
- Short feedback animation.

For Dark Space PvP:
- Larger player must sufficiently overlap smaller player.
- Use size threshold to avoid unfair near-equal consumption.

Example rule:
A player must be at least X% larger before they can consume another.

Tune during testing.

---

# 45. SPAWN SYSTEM

White Space:
- Icons spawn based on region/category/rarity.
- Prevent boring empty stretches unless intentional.
- Rare zones can be less dense.

Dark Space:
- Constant neutral-dot spawning.
- Spawn density based on population.
- Avoid spawning resources directly inside huge players.
- Protect fresh respawns briefly.

---

# 46. SAFE SPAWN

When entering Dark Space or respawning:
- Short spawn protection.
- Prevent immediate consumption.
- Spawn away from the largest nearby player.
- Allow player to orient themselves.

Spawn protection ends when:
- Timer ends, or
- Player uses offensive ability.

---

# 47. LEADERBOARDS

Dark Space leaderboards can display:
- Current size.
- Match score.
- Survival time.
- Players eaten.

Do not need every leaderboard at launch.

Recommended MVP:
**Top 10 Current Size**

Long-term:
- Daily.
- Weekly.
- All-time Intelligence.
- Forms completed.
- Rare discoveries.

---

# 48. COLLECTION SCREEN

Create a clean Collection screen.

Sections:
- All
- Food
- Nature
- Body
- Technology
- Space
- Emotion
- Animal
- Objects
- Rare
- Premium

Each collectible/form can show:
- Icon.
- Name.
- Completion percentage.
- Completed status.
- Ability.
- Rarity.

Example:

Banana
87%
Ability: Slippery Dash

Rock
100%
Completed
Ability: Harden

Galaxy
12%
Legendary

---

# 49. PLAYER PROFILE

Profile can show:
- Username.
- Dot preview.
- Intelligence level.
- Completed forms count.
- Dark Space highest size.
- Rare forms.
- AI+ badge if member.
- Selected trail/ring.
- Achievements.

Keep visual language minimal.

---

# 50. ACHIEVEMENTS

Examples:
- First Bite
- First Form
- 10 Forms
- 100 Icons Collected
- Enter Dark Space
- Survive 5 Minutes
- Eat First Player
- Reach Top 10
- Discover Legendary
- Complete One Category
- Become Gold
- 1,000 Intelligence
- Travel Long Distance

---

# 51. DAILY / WEEKLY CHALLENGES

Examples:
- Eat 20 Food icons.
- Complete 25% of a new form.
- Find 3 rare collectibles.
- Survive 3 minutes in Dark Space.
- Send a message to another player.
- Eat 100 blue dots.
- Use 3 different abilities.

Rewards:
- Intelligence.
- Cosmetic fragments.
- Premium XP for AI+ users.
- Normal free rewards for everyone.

---

# 52. SOUND

Sound design should be minimal.

Examples:
- Soft collectible pop.
- Rare collectible tone.
- Transformation pulse.
- Dark Space transition.
- Player consumed sound.
- Chat/reaction sound.
- Ability activation.

Avoid:
- Loud arcade spam.
- Constant repetitive noises.

Provide:
- Music toggle.
- Sound toggle.
- Haptics toggle.

---

# 53. HAPTICS

Use light haptics for:
- Eating collectible.
- Reaching 100%.
- Entering Dark Space.
- Ability activation.
- Being eaten.

Avoid constant vibration.

---

# 54. MUSIC

White Space:
- Minimal ambient.
- Quiet.
- Spacious.
- Optional.

Dark Space:
- Slightly more energy.
- Still minimalist.

Music should not overpower simplicity.

---

# 55. VISUAL ACCESSIBILITY

Include:
- High contrast options.
- Reduce motion.
- Disable trails.
- Disable particles.
- Larger text.
- Color + icon identification so gameplay does not rely only on color.
- Haptic feedback options.

---

# 56. PERFORMANCE

The game should perform well on modern supported iPhones.

Optimize:
- Dot rendering.
- Particle counts.
- Text labels.
- Network updates.
- Off-screen entities.
- Trail length.
- Animation.
- Emoji/icon rendering.

Avoid rendering hundreds of expensive views.

Use efficient game rendering.

---

# 57. BACKEND DATA MODEL

Suggested conceptual models.

## User
- id
- username
- createdAt
- intelligence
- intelligenceLevel
- membershipStatus
- membershipExpiration
- equippedDotSkin
- equippedRing
- equippedTrail
- equippedEmoteSet
- completedForms
- collectionProgress
- achievements
- stats
- settings

## Player Session
- userId
- worldId
- positionX
- positionY
- velocityX
- velocityY
- size
- activeForm
- hybridData
- currentEnergy
- activeAbility
- cooldowns
- lastUpdate

## World
- id
- type
- population
- seed
- region
- entities
- signals
- startedAt

## Collectible
- id
- type
- iconId
- x
- y
- rarity
- value
- spawnedAt

## Chat Message
- id
- userId
- worldId
- text
- createdAt
- expiresAt

---

# 58. REAL-TIME NETWORKING RULES

The server should control important gameplay facts.

Client can predict movement for responsiveness, but server verifies:
- Position boundaries.
- Impossible speed.
- Consumption.
- Size.
- Ability cooldown.
- Spawn.
- Rewards.
- PvP outcomes.

Use:
- Snapshot updates.
- Interpolation.
- Rate limits.
- Delta updates if useful.

Do not trust the client for:
- Size.
- premium status.
- rewards.
- form completion.
- collision win.
- currency.

---

# 59. ANTI-CHEAT

At minimum detect:
- Impossible movement speed.
- Teleporting without ability.
- Fake size.
- Invalid consumption.
- Spam chat.
- Ability spam.
- forged membership state.
- duplicate reward claims.

Log suspicious behavior.

---

# 60. MODERATION / SAFETY

Because users can type messages:

Include:
- Report.
- Block.
- Mute.
- Rate limit.
- Optional word filter.
- Server-side moderation hooks.
- No personally identifying information required for gameplay.
- Clear community rules.

Keep chat short and transient.

---

# 61. ONBOARDING

First launch should be memorable and extremely simple.

Screen:
Pure white.

After a moment:
A tiny dot appears.

Text:
**This is you.**

Then:
**Move.**

Player moves.

A small collectible appears nearby.

Example:
🍌

Text:
**Eat it.**

Player eats it.

Display:
**Banana 7%**

Then:
**Everything you eat changes you.**

After that:
Allow player to play.

Do not force a 10-page tutorial.

---

# 62. FIRST 10 MINUTES

Suggested pacing:

Minute 0–1:
- Learn movement.
- Eat first icon.

Minute 1–3:
- Discover multiple icon types.
- See transformation percentage.

Minute 3–5:
- Unlock first small ability.
- See another dot or AI dot.

Minute 5–8:
- First Signal event.

Minute 8–10:
- Collection screen unlocked.
- Dark Space shown as a future locked destination.

The player should quickly understand:
"I eat things, I change, I become stronger/different, and there is another world coming."

---

# 63. DARK SPACE FIRST ENTRY

When player unlocks Dark Space:

Show portal.

Prompt:
**Enter Dark Space?**

Short explanation:
**Grow by eating small dots. Larger dots can eat smaller dots. Your forms give you abilities.**

Transition:
- White fades.
- Dot remains.
- Background becomes black.
- Colored dots appear.
- Other players appear.

Do not use a long cinematic.

---

# 64. CORE DARK SPACE EXPERIENCE

The player should immediately see:
- Their size.
- Nearby collectible dots.
- At least some distant players.
- A simple leaderboard.
- One active ability.

They eat neutral dots.
They get larger.
They see a larger player.
They learn to escape.

This is the core tension.

---

# 65. HYBRID BUILDS

Allow players to build interesting combinations.

Examples:

## Electricity + Rock
- Faster than Rock.
- Stronger than Electricity.
- Moderate handling.

## Fire + Ice
- Can alternate heat/freeze effects.
- Lower specialized strength than pure form.

## Brain + Eye
- Excellent detection/scanning.

## Ghost + Rocket
- Escape specialist.

## Magnet + Water
- Efficient collector.

Pure forms can have stronger specialized abilities.
Hybrids provide flexibility.

---

# 66. FORM SLOTS / LOADOUT

Long-term:
Allow player to equip or preserve certain unlocked forms.

Possible system:
- One Primary Form.
- One Secondary Influence.
- One Active Ability.
- One Passive Ability.

Do not introduce all complexity at launch.

MVP:
Use current transformation as current form.

---

# 67. WORLD REGIONS

White Space can be huge without needing visual scenery.

Create invisible/content-based regions.

Examples:
- Food-rich region.
- Nature region.
- Tech region.
- Biological region.
- Rare space region.
- Unstable region.
- Premium event region.

Region changes can be communicated through:
- Spawn types.
- Subtle ambient effect.
- Tiny text.
- Dot density.

Background should remain mostly white.

---

# 68. DARK SPACE REGIONS

Dark Space can have subtle zones:
- Dense resource zone.
- Low-resource danger zone.
- Speed zone.
- Slow zone.
- Signal zone.
- Safe temporary zone.
- Legendary spawn zone.

Background remains black/dark.

Avoid traditional map tiles if possible.

---

# 69. PORTALS

Portals can connect:
- White Space → Dark Space.
- White Space regions.
- Event spaces.
- Future levels.

Portal visual should still match minimalist identity:
- Ring.
- Pulsing circle.
- Distortion.
- No giant fantasy gate.

---

# 70. FUTURE WORLDS

Design architecture so more worlds can be added.

Potential future spaces:
- Red Space.
- Zero Space.
- Mirror Space.
- Noise Space.
- Gravity Space.
- AI Core.
- Infinite Space.

Do not build all now.

But make world loading modular.

---

# 71. ECONOMY

If using currencies, keep them limited.

Suggested:
- Intelligence = progression.
- Cosmetic currency = optional.
- Premium fragments = cosmetic unlocks.

Avoid 8 currencies.

---

# 72. FREE PLAYER EXPERIENCE

Free players must be able to:
- Enter White Space.
- Collect icons.
- Complete forms.
- Unlock Dark Space.
- Play multiplayer.
- Grow.
- Eat players.
- Use chat.
- Earn abilities.
- Progress normally.

They should not feel like a demo.

---

# 73. AI+ MEMBER EXPERIENCE

AI+ adds:
- Premium dot materials.
- Premium rings.
- Premium trails.
- Premium emotes.
- Premium chat styling.
- Premium cosmetic form variants.
- AI+ collection track.
- Exclusive cosmetic collectibles.
- Custom Dot Builder later.

Premium players should look rare and impressive.

---

# 74. NOT PAY-TO-WIN

Critical rule:

A free Rock player and premium Obsidian Rock player should have equivalent base gameplay power if they use the same form.

Premium changes appearance/status, not guaranteed combat outcomes.

If premium offers convenience:
- Keep it modest.
- Do not bypass all progression.

---

# 75. NOTIFICATIONS

Optional:
- Friend online.
- Daily challenge available.
- Rare event started.
- AI+ reward ready.

Do not spam.

Ask permission appropriately.

---

# 76. ACCOUNT SYSTEM

Keep account setup simple.

Possible options:
- Sign in with Apple.
- Guest account with later upgrade.
- Minimal username system.

Do not force excessive personal information.

---

# 77. SETTINGS

Include:
- Sound.
- Music.
- Haptics.
- Reduce motion.
- Trail visibility.
- Chat visibility.
- Blocked users.
- Notifications.
- Account.
- Restore purchases.
- Privacy.
- Terms.

---

# 78. APP STORE READINESS

Prepare for:
- Privacy policy.
- Terms.
- Content moderation explanation.
- In-app purchase metadata.
- Subscription metadata.
- Screenshots.
- App icon.
- Age rating.
- Data collection disclosures.
- Multiplayer/user-generated content review requirements.

If users can type messages, treat that as user-generated content and implement appropriate safety controls.

---

# 79. ART STYLE

The game should NOT look:
- Cartoon-heavy.
- 3D-realistic.
- Like a spaceship game.
- Like a character RPG.
- Like a busy mobile casino.
- Like a neon overload.

It SHOULD look:
- Minimal.
- Modern.
- Strange.
- Clean.
- Intelligent.
- Spacious.
- Recognizable.

---

# 80. WHITE SPACE COLORS

Background:
- Pure white or near-white.

Player:
- Black/gray initially.

Collectibles:
- Use their natural/icon-related colors.

UI:
- Black/gray text.
- Minimal accents.

Avoid unnecessary blue UI branding unless specifically selected later.

---

# 81. DARK SPACE COLORS

Background:
- Pure or near-black.

Neutral collectibles:
- Bright blue.
- Pink.
- Purple.
- Yellow.
- White.
- Rare gold.

Player dots:
- Transformation colors.
- Premium materials.

UI:
- White/light gray.

---

# 82. DOT VISUAL RULE

Every visual upgrade must pass this question:

**Is the player still obviously a dot?**

If no, redesign it.

Examples allowed:
- Gold circle.
- Glass circle.
- Circle with lightning.
- Circle with small icon.
- Circle with ring.
- Circle with trail.

Examples not allowed:
- Full banana-shaped character.
- Full robot body.
- Human.
- Spaceship.
- Dragon model.

---

# 83. MVP CONTENT

For the first playable release, do NOT attempt hundreds of fully programmed powers.

Start with around 20–30 collectible types.

Suggested starter set:

- 🍌 Banana
- 🍎 Apple
- 🍕 Pizza
- ☕ Coffee
- 💧 Water
- 🔥 Fire
- ⚡ Lightning
- 🧊 Ice
- 🌿 Leaf
- 🪨 Rock
- ☁️ Cloud
- ⭐ Star
- 🪐 Planet
- 🚀 Rocket
- 🤖 Robot
- ⚙️ Gear
- 🔋 Battery
- 🧠 Brain
- 👁️ Eye
- 🩸 Blood
- ❤️ Heart
- 💀 Skull
- 🛡️ Shield
- 🧲 Magnet
- 💎 Diamond
- 🔮 Crystal Ball
- 🐢 Turtle
- 🐇 Rabbit
- 👻 Ghost
- 👑 Crown

Use data-driven configuration so more can be added later.

---

# 84. MVP ABILITIES

Implement a smaller number of meaningful abilities first.

Example MVP abilities:
- Banana: slippery dash.
- Rock: temporary harden.
- Fire: damage pulse.
- Ice: slow pulse.
- Electricity: speed boost.
- Water: smooth speed/escape.
- Brain: scan.
- Eye: view range.
- Magnet: pull collectibles.
- Rocket: dash.
- Shield: temporary shield.
- Ghost: phase/escape.

Other icons can initially modify stats without unique active abilities.

---

# 85. MVP WHITE SPACE

Must include:
- Huge white world.
- Smooth movement.
- Collectible icon dots.
- Percentage transformation.
- At least 20 icon types.
- Completion at 100%.
- Collection page.
- Intelligence progression.
- Basic Signals.
- Other online dots or AI dots.
- Chat above dots.

---

# 86. MVP DARK SPACE

Must include:
- Black world.
- Real-time multiplayer.
- Neutral colored growth dots.
- Size growth.
- Larger eats smaller.
- Respawn.
- One active ability.
- Top 10 leaderboard.
- Messages above dots.
- Basic anti-cheat/server validation.

---

# 87. MVP PREMIUM

Must include:
- AI+ membership.
- Gold Dot.
- Diamond Dot.
- Black Gold Dot.
- Galaxy Dot.
- 2–3 premium trails.
- 2–3 premium rings.
- Premium chat accent.
- Restore purchases.

Do not build 30 membership levels before core game works.

---

# 88. DEVELOPMENT PHASES

## Phase 1 — Prototype
- One dot.
- White background.
- Movement.
- Collectible spawning.
- Eating collision.
- Percentage change.
- Simple transformation color.

## Phase 2 — White Space Core
- Multiple icons.
- Collection.
- Abilities.
- Intelligence.
- Missions/Signals.
- Save progress.

## Phase 3 — Multiplayer Foundation
- Real-time movement.
- Rooms.
- Position sync.
- Player names/messages.
- Server validation.

## Phase 4 — Dark Space
- Black map.
- Size.
- Neutral dots.
- PvP consumption.
- Respawn.
- Leaderboard.

## Phase 5 — Premium
- Store.
- Membership.
- Premium skins.
- Entitlements.
- Restore purchase.

## Phase 6 — Polish
- Audio.
- Haptics.
- Accessibility.
- Tutorial.
- Performance.
- Moderation.
- App Store assets.

---

# 89. TECHNICAL STRUCTURE

Use a clean modular architecture.

Suggested conceptual modules:

- App
- Authentication
- PlayerState
- WorldEngine
- WhiteSpaceWorld
- DarkSpaceWorld
- Collectibles
- TransformationEngine
- AbilitySystem
- Multiplayer
- Networking
- Chat
- Moderation
- Collection
- Missions
- Signals
- Premium
- Store
- Audio
- Haptics
- Settings
- Analytics

Avoid one giant game file.

---

# 90. TRANSFORMATION ENGINE REQUIREMENTS

The Transformation Engine should:
- Accept collectible absorption.
- Update percentages.
- Handle decay/replacement rules if used.
- Calculate dominant form.
- Calculate hybrid influence.
- Update visual state.
- Unlock completed forms.
- Apply stats.
- Apply active/passive abilities.

Make the logic deterministic and testable.

---

# 91. PERCENTAGE RULES

Define clear rules.

Example model:
- Player has a transformation composition totaling 100 influence points after enough collection.
- New consumption pushes composition toward the new type.

Alternative simpler MVP:
- Each form has independent completion progress.
- Active form is the most recently pursued type.

Recommended for MVP:
Use independent completion progress + current active transformation.

Then later introduce deep hybrid composition.

This reduces complexity.

---

# 92. FORM PROGRESS EXAMPLE

Player:
- Banana collection completion: 65%.
- Rock completion: 100% (unlocked).
- Fire completion: 22%.

Current active transformation:
Banana 65%.

Visual:
Mostly normal + growing yellow influence.

When Banana hits 100%:
Unlock Banana form.

This makes permanent collection easy to understand.

---

# 93. OPTIONAL ADVANCED HYBRID SYSTEM

After MVP, add a separate equipped hybrid system.

Example:
Choose:
- Primary: Electricity.
- Secondary: Rock.

Then create stat mix.

Do not make collection percentages impossible to understand.

---

# 94. CHAT SAFETY

Message length:
Keep short.

Example:
Maximum 60–100 characters.

Rate limit:
Example one message every few seconds.

Allow:
- Mute chat globally.
- Hide chat.
- Block player.
- Report player.

Messages disappear visually after seconds but moderation logs may be retained according to privacy policy and safety needs.

---

# 95. PLAYER INTERACTIONS

Tapping another player can open a small contextual sheet:
- Profile.
- Mute.
- Block.
- Report.
- Add/follow later.
- Send quick reaction.

Do not stop gameplay with a full screen unnecessarily.

---

# 96. EVENT EXAMPLE — WHITE SPACE

Player sees:
**SIGNAL: UNKNOWN OBJECT — 1,240 units**

They travel toward it.

They find several icons moving in a pattern.

Objective:
**Eat only the blue icons. Avoid red.**

Reward:
- Rare Diamond fragment.
- +50 Intelligence.

---

# 97. EVENT EXAMPLE — DARK SPACE

World message:
**GOLD CORE DETECTED**

A Gold Core appears.

Players race toward it.

Rules:
- Core moves slowly.
- Player must remain near it for a short time to claim.
- Large players can contest.
- Premium member receives cosmetic progression.
- Free player can receive Intelligence or a free-event reward if they participate, depending on design.

Do not create a useless event for free players.

---

# 98. PLAYER STORY EXAMPLE

A new player enters.

They are:
`•`

They eat:
🍌

Banana 7%.

Then:
⚡

Electricity 5%.

They continue collecting Banana.

Banana reaches 100%.

They unlock:
**Banana Form**

They later complete:
- Rock.
- Eye.
- Fire.
- Water.

They reach enough Intelligence.

They find:
**Dark Portal**

They enter Dark Space.

They are initially small.

They eat blue and pink dots.

They grow.

They see another player:
"friendly?"
●

They answer:
"yes"

A huge player appears.

Both run.

The user activates Banana Dash and escapes.

Later they grow large enough to eat another player.

This should feel like a complete game story without ever requiring a humanoid character.

---

# 99. PREMIUM PLAYER STORY EXAMPLE

AI+ player has:
- Black Gold Dot.
- Gold Ring.
- Electric Trail.

They enter White Space.

They still collect the same gameplay items as free users.

They complete Rock.

Their premium cosmetic variant:
**Obsidian Gold Rock**

Same core gameplay stats as Rock.

They enter Dark Space.

Other users can recognize them as premium/rare by appearance.

They look impressive but are still beatable.

---

# 100. DESIGN LANGUAGE FOR TEXT

Use short text.

Good:
- Eat.
- Move.
- Run.
- Signal detected.
- Form complete.
- Dark Space unlocked.
- You were eaten.
- 72% Banana.
- Intelligence +5.

Avoid:
Long paragraphs during active gameplay.

Long descriptions belong in:
- Collection.
- Profile.
- Help.
- Settings.

---

# 101. ERROR STATES

Handle gracefully:
- Lost connection.
- Reconnecting.
- Server full.
- Purchase failed.
- Purchase pending.
- Restore failed.
- Username invalid.
- Chat unavailable.
- Data sync failed.

Never silently lose progress.

---

# 102. SAVE SYSTEM

Persist:
- User progression.
- Form completion.
- Collection.
- Intelligence.
- Achievements.
- Premium ownership.
- Cosmetics.
- Settings.

Match/current session data can be temporary.

Use cloud/server persistence for important progression.

---

# 103. ANALYTICS

Track privacy-respecting gameplay events such as:
- Tutorial completion.
- First collectible.
- First completed form.
- Dark Space unlock.
- Dark Space entry.
- First PvP win.
- Death.
- Session length.
- Most-used forms.
- Membership conversion.
- Retention.

Do not collect unnecessary personal information.

---

# 104. BALANCING TARGETS

The game should feel:
- Fast enough to be fun.
- Slow enough for progression to matter.

Example initial targets for testing only:
- First collectible in <30 seconds.
- First meaningful transformation progress in first minute.
- First form completion within first session.
- Dark Space unlock after meaningful but not exhausting play.
- Respawn quickly after defeat.

Tune with playtesting.

---

# 105. ANTI-FRUSTRATION

Avoid:
- Spawning under huge player.
- Losing permanent forms.
- Rare item stolen with no counterplay every time.
- Long unskippable tutorial.
- Full-screen ad interruptions during active play.
- Excessive premium popups.
- Long respawn timers.

---

# 106. FUTURE FEATURES

Do not build all initially, but architecture should allow:
- Parties.
- Teams.
- Clans.
- Player-created signals.
- Trading.
- Seasonal events.
- World bosses represented as giant dots.
- Cooperative survival.
- Tournaments.
- More worlds.
- Custom rooms.
- Private matches.
- Advanced AI-controlled agents.
- Player-created dot presets.
- Spectator mode.

---

# 107. POSSIBLE BOSS SYSTEM

Boss must still fit dot identity.

Example:
A massive black circle appears.

It has:
- Rings.
- Orbiting mini-dots.
- Pulse attacks.

Players cooperate.

No dragon model required.

Boss can represent:
- Black Hole.
- Virus.
- Core.
- Unknown AI.

---

# 108. SEASONAL EVENTS

Examples:
- Halloween: Ghost/Skull focus.
- Winter: Ice/Snow.
- Spring: Flowers.
- Space Event: Galaxy/Comet.
- Gold Week: Gold Core.

Seasonal cosmetics should remain optional.

---

# 109. CUSTOMIZATION PRIORITY

Always prioritize:
1. Dot material.
2. Dot ring.
3. Trail.
4. Icon badge.
5. Chat style.
6. Emote.

Do not overload customization.

---

# 110. APP ICON CONCEPT

App icon could be extremely minimal.

Ideas:
- Single black dot on white background.
- White dot on black background.
- Split white/black representing White Space and Dark Space.
- Small "AI" text only if readable.

Prefer iconic simplicity.

---

# 111. APP STORE SCREENSHOT STORY

Possible sequence:

1. White screen + small dot:
   **THIS IS YOU.**

2. Dot approaching icon collectibles:
   **EAT ANYTHING.**

3. Transformation percentage:
   **EVERYTHING CHANGES YOU.**

4. Completed forms:
   **BECOME SOMETHING NEW.**

5. Dark portal:
   **ENTER DARK SPACE.**

6. Multiplayer black map:
   **GROW. SURVIVE.**

7. Large player chasing smaller:
   **BIGGER DOTS EAT SMALLER DOTS.**

8. Player chat:
   **TALK TO ANYONE.**

9. Premium forms:
   **AI+ — STAND OUT.**

---

# 112. SHORT GAME DESCRIPTION

AI is a minimalist online evolution game where you begin as a tiny dot inside a massive White Space. Eat icon-based objects, absorb their properties, transform gradually, unlock abilities, and complete new forms. When you are ready, enter Dark Space, grow by consuming smaller dots, escape larger players, use your abilities, and communicate with other players directly above your dot.

You are always a dot.

What changes is what you become.

---

# 113. CORE TAGLINE

Recommended:
**Eat. Change. Evolve.**

Other possibilities:
- Become Anything.
- Start as a Dot.
- Everything Changes You.
- Enter the White Space.
- Grow Into Something Else.
- You Are the Dot.

---

# 114. MASTER PRODUCT RULES

The final game MUST preserve these rules:

- The player is always a dot.
- White Space is white/minimal.
- Dark Space is dark/competitive.
- Icon collectibles drive transformation.
- Transformations happen gradually by percentage.
- Reaching 100% unlocks forms.
- Many keyboard/emoji-style icons can become collectibles.
- Different forms have different gameplay properties.
- Players can eventually enter Dark Space.
- Dark Space uses bigger-eats-smaller gameplay.
- Small colored dots increase player size.
- Players can type temporary messages above their dots.
- Online multiplayer is the main experience.
- AI-controlled dots can supplement populations.
- Premium membership provides much better-looking dots, rings, trails, emotes, and cosmetic variants.
- Premium must not automatically guarantee gameplay superiority.
- The game must remain visually minimalist.
- The systems must be data-driven and scalable.

---

# 115. BUILD ORDER

When implementing, prioritize in this exact order:

1. Render player dot.
2. Smooth movement.
3. Large White Space.
4. Spawn collectible icon dots.
5. Eat collision.
6. Transformation percentage.
7. Visual gradual transformation.
8. Save progress.
9. Collection screen.
10. Basic abilities.
11. Real-time online movement.
12. Chat above dots.
13. Signals/missions.
14. Dark Space.
15. Neutral growth dots.
16. Size growth.
17. Bigger-eats-smaller PvP.
18. Respawn.
19. Leaderboard.
20. Premium membership.
21. Gold/Diamond/Galaxy premium skins.
22. Trails/rings.
23. Moderation/report/block.
24. Audio/haptics.
25. Performance polish.
26. App Store readiness.

---

# 116. MVP SUCCESS CRITERIA

A build is considered a successful first version when a user can:

1. Launch the game.
2. See themselves as a dot in White Space.
3. Move smoothly.
4. Eat multiple icon collectibles.
5. Watch their dot gradually change.
6. Reach 100% and unlock at least one form.
7. Save progress.
8. See other players online.
9. Type a short message above their dot.
10. Unlock and enter Dark Space.
11. Eat small colored dots to grow.
12. Escape larger players.
13. Eat smaller players when large enough.
14. Respawn after being eaten.
15. Use at least one transformation ability.
16. View a leaderboard.
17. View collection/progression.
18. Subscribe to AI+ through Apple's supported in-app purchase system.
19. Equip at least one premium dot cosmetic.
20. Restore purchases.

---

# 117. FINAL CREATIVE DIRECTION

Do not try to make the game impressive by filling the screen.

Make it impressive by taking something extremely simple—a dot—and giving that dot a huge number of possibilities.

The emotional progression should be:

At first:
**I am nothing.**

Then:
**I can eat things.**

Then:
**The things I eat are changing me.**

Then:
**I can become different things.**

Then:
**There are other players here.**

Then:
**There is another world.**

Then:
**I need to survive.**

Then:
**I can become powerful.**

Then:
**My dot is completely unique.**

The game should be understandable in seconds and capable of expanding for years.

The visual identity is not a limitation.

The dot is the identity.

**Build AI around one simple question:**

# WHAT WILL YOUR DOT BECOME?
