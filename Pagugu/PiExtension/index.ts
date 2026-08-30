// L3 COORD: Pagugu/PiExtension/index.ts
// INPUT: Pi 已加载 Skill、用户输入，以及 Pagugu 独占 ~/.pi/agent/pagugu/visibility.json。
// OUTPUT: 从模型上下文隐藏 hidden/disabled Skill，并阻断 disabled Skill 的 /skill:name。
// POS: PiExtension 模块的 Pi 运行时入口。does not write 配置、settings.json、SKILL.md 或触发 reload。
// TEST: repo://PaguguTests/PiExtensionHealthTests.swift；API 合同见 Pi 官方 docs/extensions.md。
// Hidden-skill behavior is inspired by jvm/pi-skillful.
// MIT License — Copyright (c) 2026 Jose Mocito
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.
// Source license: https://github.com/jvm/pi-skillful/blob/main/LICENSE

import { readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { formatSkillsForPrompt } from "@earendil-works/pi-coding-agent";

export const PAGUGU_PI_EXTENSION_VERSION = "1";

const EMPTY_VISIBILITY = {
	hiddenSkills: [],
	disabledSkills: [],
};

function readVisibilityDocument() {
	const configurationPath = join(homedir(), ".pi", "agent", "pagugu", "visibility.json");
	try {
		const value = JSON.parse(readFileSync(configurationPath, "utf8"));
		if (!isVisibilityDocument(value)) {
			throw new Error("invalid Pagugu visibility document");
		}
		return value;
	} catch {
		// Missing, unreadable, or damaged policy must not prevent Pi from starting.
		return EMPTY_VISIBILITY;
	}
}

function isVisibilityDocument(value) {
	if (typeof value !== "object" || value === null) return false;
	const candidate = value;
	if (!isSkillNameArray(candidate.hiddenSkills) || !isSkillNameArray(candidate.disabledSkills)) {
		return false;
	}
	const hidden = new Set(candidate.hiddenSkills);
	const disabled = new Set(candidate.disabledSkills);
	return hidden.size === candidate.hiddenSkills.length
		&& disabled.size === candidate.disabledSkills.length
		&& candidate.hiddenSkills.every((name) => !disabled.has(name));
}

function isSkillNameArray(value) {
	return Array.isArray(value) && value.every((item) => typeof item === "string" && item.length > 0);
}

function replaceSkillSection(systemPrompt, loadedSkills, hiddenSkillNames) {
	const visibleSkills = loadedSkills.filter((skill) => !hiddenSkillNames.has(skill.name));
	if (visibleSkills.length === loadedSkills.length) return undefined;
	const currentSection = formatSkillsForPrompt(loadedSkills);
	if (!systemPrompt.includes(currentSection)) return undefined;
	return systemPrompt.replace(currentSection, formatSkillsForPrompt(visibleSkills));
}

export default function paguguVisibilityExtension(pi) {
	const visibility = readVisibilityDocument();
	const disabledSkillNames = new Set(visibility.disabledSkills);
	const hiddenSkillNames = new Set([
		...visibility.hiddenSkills,
		...visibility.disabledSkills,
	]);

	pi.on("before_agent_start", (event) => {
		const loadedSkills = event.systemPromptOptions.skills;
		if (!loadedSkills || loadedSkills.length === 0 || hiddenSkillNames.size === 0) return;
		const systemPrompt = replaceSkillSection(event.systemPrompt, loadedSkills, hiddenSkillNames);
		return systemPrompt === undefined ? undefined : { systemPrompt };
	});

	pi.on("input", (event, ctx) => {
		const match = event.text.trimStart().match(/^\/skill:([^\s]+)(?:\s|$)/);
		const skillName = match?.[1];
		if (!skillName || !disabledSkillNames.has(skillName)) {
			return { action: "continue" };
		}
		if (ctx.hasUI) {
			ctx.ui.notify(`[Pagugu] 已阻止调用全禁用 Skill：${skillName}`, "error");
		}
		return { action: "handled" };
	});
}
