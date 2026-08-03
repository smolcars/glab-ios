#!/bin/zsh

set -euo pipefail

script_directory="${0:A:h}"
repository_root="${script_directory:h}"
manifest_path="${repository_root}/Configuration/GitLabIcons.json"
asset_catalog="${repository_root}/Glab/Resources/Assets.xcassets"

for command_name in curl jq; do
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "Missing required command: ${command_name}" >&2
        exit 1
    fi
done

package_name="$(jq -er '.package' "${manifest_path}")"
package_version="$(jq -er '.version' "${manifest_path}")"
package_tag="$(jq -er '.tag' "${manifest_path}")"
source_repository="$(jq -er '.source' "${manifest_path}")"
encoded_tag="$(
    jq -nr --arg tag "${package_tag}" \
        '$tag | @uri'
)"
source_root="${source_repository}/-/raw/${encoded_tag}/packages/gitlab-svgs/sprite_icons"

while IFS= read -r icon_name; do
    image_set="${asset_catalog}/${icon_name}.imageset"
    svg_path="${image_set}/${icon_name}.svg"
    temporary_svg="$(mktemp)"
    trap 'rm -f "${temporary_svg}"' EXIT

    curl --fail --location --silent --show-error \
        "${source_root}/${icon_name}.svg" \
        --output "${temporary_svg}"

    mkdir -p "${image_set}"
    mv "${temporary_svg}" "${svg_path}"
    trap - EXIT

    jq --null-input \
        --arg filename "${icon_name}.svg" \
        '{
          images: [
            {
              filename: $filename,
              idiom: "universal"
            }
          ],
          info: {
            author: "xcode",
            version: 1
          },
          properties: {
            "preserves-vector-representation": true,
            "template-rendering-intent": "template"
          }
        }' > "${image_set}/Contents.json"
done < <(jq -er '.icons[]' "${manifest_path}")

echo "Synced GitLab SVG icons from ${package_name} ${package_version}."
