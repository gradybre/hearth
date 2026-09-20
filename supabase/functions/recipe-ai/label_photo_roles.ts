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

/// What a label request was actually for, judged by the photos it carried
/// (spec R11).
///
/// Roles are still untrusted as *content* — nothing here reaches a prompt as
/// free text — but they are trustworthy as a statement of what the caller
/// selected, and that is the one thing that decides whether a reply may state
/// nutrition at all. A photo set with no panel in it cannot have read one.
export interface LabelRequestIntent {
  nutrition: boolean;
  package: boolean;
}

/// The permissive answer, used whenever the roles cannot be classified.
///
/// Failing open matters here: a client too old to send roles, or one whose
/// array does not line up with its images, must keep working exactly as it
/// did. The cost of gating one of those by mistake is a panel somebody
/// photographed being thrown away, which is worse than the pollution the gate
/// exists to stop.
const PERMISSIVE: LabelRequestIntent = { nutrition: true, package: true };

export function labelRequestIntent(
  roles: unknown,
  count: number,
): LabelRequestIntent {
  if (!Array.isArray(roles) || count === 0 || roles.length !== count) {
    return PERMISSIVE;
  }
  const known = roles.filter(
    (role) => role === 'nutrition' || role === 'package',
  );
  if (known.length !== roles.length) return PERMISSIVE;
  return {
    nutrition: known.includes('nutrition'),
    package: known.includes('package'),
  };
}
