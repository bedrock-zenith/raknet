import {
    appendFileSync,
    readdirSync,
    readFileSync,
    statSync,
    writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ORG_NAME = "Bedrock Zenith";
const PROJECT_NAME = "Zenith Raknet";

const licenseText = `SPDX-License-Identifier: LGPL-3.0-or-later
============================================================================
 ${PROJECT_NAME} - Minecraft Bedrock Raknet
 Copyright (C) 2026 ${ORG_NAME}
 https://github.com/bedrock-zenith/raknet
============================================================================

This file is part of ${PROJECT_NAME}.

${PROJECT_NAME} is free software: you can redistribute it and/or modify
it under the terms of the GNU Lesser General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

${PROJECT_NAME} is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
GNU Lesser General Public License for more details.

You should have received a copy of the GNU Lesser General Public License
along with ${PROJECT_NAME}. If not, see <https://www.gnu.org/licenses/>.`
    .split("\n")
    .map((str) => "//  " + str)
    .join("\n");

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const srcFolder = join("src");

recursiveReadFolder(srcFolder);

/**
 * @param {import("node:fs").PathLike} folderPath
 * @returns {void}
 */
function recursiveReadFolder(folderPath) {
    for (const path of readdirSync(folderPath).map((p) =>
        join(folderPath, p),
    )) {
        recursiveRead(path);
    }
}

/**
 * @param {import("node:fs").PathLike} path
 * @returns {void}
 */
function recursiveRead(path) {
    if (statSync(path).isDirectory()) {
        recursiveReadFolder(path);
    } else {
        processFile(path);
    }
}

/**
 * @param {import("node:fs").PathLike} path
 * @returns {void}
 */
function processFile(path) {
    if (!path.endsWith(".zig")) {
        return;
    }

    let fileContents = readFileSync(path, { encoding: "utf-8" });

    fileContents = cleanOldLicenseText(fileContents);

    writeFileSync(path, licenseText);
    appendFileSync(path, "\n\n");
    appendFileSync(path, fileContents);
}

/**
 * @param {string} fileContents
 * @returns {string}
 */
function cleanOldLicenseText(fileContents) {
    if (
        !fileContents
            .split("\n")[0]
            .includes("SPDX-License-Identifier: LGPL-3.0-or-later")
    ) {
        return fileContents;
    }

    const array = fileContents.split("\n");
    let index = 0;
    for (const line of array) {
        ++index;
        if (line.trim().startsWith("//")) continue;
        break;

        // if (line.trim().startsWith("//")) {
        //     const start = fileLineByLine[i] === "" ? i + 1 : i;
        //     return fileLineByLine
        //         .splice(start, fileLineByLine.length)
        //         .join("\n");
        // }
        // else lines.push(line);
        // ++i;
    }
    return array.slice(index).join("\n");
}
