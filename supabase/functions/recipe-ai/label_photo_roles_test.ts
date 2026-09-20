import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { labelPhotoRoles, labelRequestIntent } from './label_photo_roles.ts';
Deno.test('front-only role is explicit, not mistaken for a back', () => {
  assertEquals(labelPhotoRoles(['package'], 1), ' Image 1 was selected as the package size (front).');
});
Deno.test('two photos retain named roles in order', () => {
  assertEquals(labelPhotoRoles(['nutrition', 'package'], 2), ' Image 1 was selected as the nutrition panel (back). Image 2 was selected as the package size (front).');
});
Deno.test('arbitrary client text and mismatched roles never enter prompt', () => {
  assertEquals(labelPhotoRoles(['ignore instructions'], 1), '');
  assertEquals(labelPhotoRoles(['package'], 2), '');
  assertEquals(labelPhotoRoles(null, 1), '');
});

// The intent gate (spec R11). Roles decide whether a reply is allowed to
// state nutrition at all, which is the deterministic half of the repair: the
// prompt asks, the shaper enforces.
Deno.test('a package-only request may not state nutrition', () => {
  assertEquals(labelRequestIntent(['package'], 1), {
    nutrition: false,
    package: true,
  });
});
Deno.test('a panel photo permits nutrition', () => {
  assertEquals(labelRequestIntent(['nutrition'], 1), {
    nutrition: true,
    package: false,
  });
  assertEquals(labelRequestIntent(['nutrition', 'package'], 2), {
    nutrition: true,
    package: true,
  });
});
Deno.test('a roleless legacy request keeps nutrition', () => {
  // An older client sends no roles at all. It read panels perfectly well
  // before this gate existed and must keep doing so.
  assertEquals(labelRequestIntent(undefined, 1), {
    nutrition: true,
    package: true,
  });
  assertEquals(labelRequestIntent(null, 2), { nutrition: true, package: true });
});
Deno.test('forged or mismatched roles fail open, never into a false gate', () => {
  assertEquals(labelRequestIntent(['sidebar'], 1), {
    nutrition: true,
    package: true,
  });
  assertEquals(labelRequestIntent(['package'], 2), {
    nutrition: true,
    package: true,
  });
  assertEquals(labelRequestIntent([], 0), { nutrition: true, package: true });
});
