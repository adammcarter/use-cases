import type { HostSurface, LoadedUseCase, MatrixSnapshot, UseCaseV1 } from "./types.js";

export type UseCaseQuery = {
  valueTiers?: readonly UseCaseV1["value_tier"][];
  journeyRoles?: readonly UseCaseV1["journey_role"][];
  lifecycles?: readonly UseCaseV1["lifecycle"][];
  hostSurfaces?: readonly HostSurface[];
  tagsAny?: readonly string[];
  tagsAll?: readonly string[];
  changedPaths?: readonly string[];
};

//: @use-case:matrix.product.coverage_by_value_and_journey
export function queryUseCases(snapshot: MatrixSnapshot, query: UseCaseQuery = {}): LoadedUseCase[] {
  return snapshot.addressableUseCases
    .filter((item) => matchesValueTier(item, query))
    .filter((item) => matchesJourneyRole(item, query))
    .filter((item) => matchesLifecycle(item, query))
    .filter((item) => matchesHostSurface(item, query))
    .filter((item) => matchesTags(item, query))
    .filter((item) => matchesChangedPaths(item, query))
    .sort((left, right) => left.value.id.localeCompare(right.value.id));
}
//: @use-case:end matrix.product.coverage_by_value_and_journey

function matchesValueTier(item: LoadedUseCase, query: UseCaseQuery): boolean {
  return !query.valueTiers?.length || query.valueTiers.includes(item.value.value_tier);
}

function matchesJourneyRole(item: LoadedUseCase, query: UseCaseQuery): boolean {
  return !query.journeyRoles?.length || query.journeyRoles.includes(item.value.journey_role);
}

function matchesLifecycle(item: LoadedUseCase, query: UseCaseQuery): boolean {
  return !query.lifecycles?.length || query.lifecycles.includes(item.value.lifecycle);
}

function matchesHostSurface(item: LoadedUseCase, query: UseCaseQuery): boolean {
  if (!query.hostSurfaces?.length) {
    return true;
  }
  if (!item.value.host_applicability?.length) {
    return true;
  }
  return item.value.host_applicability.some(
    (host) => host.supported && query.hostSurfaces?.includes(host.host_surface)
  );
}

function matchesTags(item: LoadedUseCase, query: UseCaseQuery): boolean {
  const tags = new Set(item.value.tags ?? []);
  const anyOk = !query.tagsAny?.length || query.tagsAny.some((tag) => tags.has(tag));
  const allOk = !query.tagsAll?.length || query.tagsAll.every((tag) => tags.has(tag));
  return anyOk && allOk;
}

function matchesChangedPaths(item: LoadedUseCase, query: UseCaseQuery): boolean {
  if (!query.changedPaths?.length) {
    return true;
  }
  const changed = new Set(query.changedPaths.map(normalizePath));
  return (item.value.source_refs ?? []).some(
    (sourceRef) => sourceRef.kind === "file" && changed.has(normalizePath(sourceRef.path))
  );
}

function normalizePath(path: string): string {
  return path.replaceAll("\\", "/").replace(/^\.\//, "");
}
