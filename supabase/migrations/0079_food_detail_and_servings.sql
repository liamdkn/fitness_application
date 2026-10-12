-- Finer nutrient detail on foods, and named serving sizes ("1 medium") that
-- resolve to grams. See docs/food-database-master-brief.md.
--
-- The detail columns are nullable: rows that came before them don't have the
-- figures until they are re-synced or re-seeded, and "unknown" is not "zero".
alter table foods
  add column sugar_g numeric(6, 2) check (sugar_g >= 0),
  add column saturated_fat_g numeric(6, 2) check (saturated_fat_g >= 0),
  add column cholesterol_mg numeric(7, 2) check (cholesterol_mg >= 0),
  add column potassium_mg numeric(7, 2) check (potassium_mg >= 0);

-- Discrete serving options alongside grams. A food's quantity keeps meaning
-- grams / serving_size; picking "1 medium" just resolves to a gram amount.
create table food_servings (
  id uuid primary key default gen_random_uuid(),
  food_id uuid not null references foods(id) on delete cascade,
  label text not null,
  grams numeric(8, 2) not null check (grams > 0),
  sort_order int not null default 0
);

create index food_servings_food_id_idx on food_servings (food_id);

alter table food_servings enable row level security;

-- Readable wherever the food itself is readable (the shared catalogue, or your own).
create policy "food_servings_select_with_food"
  on food_servings for select
  using (exists (
    select 1 from foods f
    where f.id = food_servings.food_id
      and (f.is_custom = false or f.created_by = auth.uid())
  ));

-- Only the owner of a custom food can add or change its servings.
create policy "food_servings_write_own_custom"
  on food_servings for all
  using (exists (
    select 1 from foods f
    where f.id = food_servings.food_id and f.is_custom = true and f.created_by = auth.uid()
  ))
  with check (exists (
    select 1 from foods f
    where f.id = food_servings.food_id and f.is_custom = true and f.created_by = auth.uid()
  ));

-- Which size was picked, for showing "1 medium banana" instead of "118 g".
alter table meal_entries add column serving_id uuid references food_servings(id) on delete set null;
alter table saved_meal_items add column serving_id uuid references food_servings(id) on delete set null;
