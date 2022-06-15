import { TokenSwappedEvent } from '../types/premium/mocks/MockBalancerLib2';

import { addNamedEvent, EventFactory, wrap } from './event-wrapper';

const stub = null as unknown;

export const Events = {
  TokenSwapped: wrap(stub as TokenSwappedEvent),
};

Object.entries(Events).forEach(([name, factory]) => addNamedEvent(factory, name));

export const eventByName = (s: string): EventFactory => Events[s] as EventFactory;
