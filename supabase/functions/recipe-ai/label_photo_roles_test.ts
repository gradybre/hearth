import { assertEquals } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { labelPhotoRoles } from './label_photo_roles.ts';
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
