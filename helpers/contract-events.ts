import { ProxyCreatedEvent } from '../types/contracts/governance/ProxyCatalog';
import { TokenSwappedEvent } from '../types/contracts/premium/mocks/MockBalancerLib2';

import { addNamedEvent, EventFactory, wrap } from './event-wrapper';

const stub = null as unknown;

export const Events = {
  TokenSwapped: wrap(stub as TokenSwappedEvent),
  ProxyCreated: wrap(stub as ProxyCreatedEvent),
};

Object.entries(Events).forEach(([name, factory]) => addNamedEvent(factory, name));

export const eventByName = (s: string): EventFactory => Events[s] as EventFactory;
