-- The seed catalogue stored some serving units as "g medium", "g tbsp", "ml cup"
-- and so on. The app only weighs or scales a food whose unit is exactly "g" or
-- "ml", so those could not be weighed on the scale (avocado was one). The unit
-- becomes plain g / ml; serving_size and the macros (which are per serving_size)
-- are untouched, so every logged entry keeps its meaning.
update foods
set serving_unit = 'g'
where source = 'seed' and serving_unit like 'g %';

update foods
set serving_unit = 'ml'
where source = 'seed' and serving_unit like 'ml %';

-- Eggs were counted ("egg", "egg white") with no weight. As grams (a large egg
-- is about 50 g, a white about 33 g) they can be weighed and given size options;
-- the figures are per serving_size as before, so entries still mean the same.
update foods set serving_size = 50, serving_unit = 'g'
where source = 'seed' and name = 'Egg' and serving_unit = 'egg';

update foods set serving_size = 33, serving_unit = 'g'
where source = 'seed' and name = 'Egg White' and serving_unit = 'egg white';
