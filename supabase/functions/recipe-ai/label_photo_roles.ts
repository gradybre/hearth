// Roles are untrusted client metadata. Only these fixed labels enter a prompt;
// the image itself remains the source of the extracted facts.
export function labelPhotoRoles(roles: unknown, count: number): string {
  if (!Array.isArray(roles) || roles.length !== count) return '';
  return roles.map((role, index) => {
    const label = role === 'nutrition' ? 'nutrition panel (back)'
      : role === 'package' ? 'package size (front)' : null;
    return label ? ` Image ${index + 1} was selected as the ${label}.` : '';
  }).join('');
}
