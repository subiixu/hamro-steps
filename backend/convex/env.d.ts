// Convex's runtime provides `process.env`; this avoids pulling in @types/node.
declare const process: { env: Record<string, string | undefined> };
