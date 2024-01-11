/*
 * Copyright [1999-2015] Wellcome Trust Sanger Institute and the EMBL-European Bioinformatics Institute
 * Copyright [2016-2024] EMBL-European Bioinformatics Institute
 * 
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * 
 *      http://www.apache.org/licenses/LICENSE-2.0
 * 
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

package org.ensembl.hive;

import static org.junit.Assert.*;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.ensembl.hive.ParamContainer;
import org.junit.Test;

/**
 * Unit tests for param handling
 * @author dstaines
 *
 */
public class ParamContainerTest {

	@Test
	public void testSimple() {
		Map<String,Object> p = new HashMap<>();
		p.put("one","1");
		ParamContainer c = new ParamContainer(p);
		assertEquals(p.get("one"), c.getParam("one"));
	}
	
	@Test
	public void testArray() {
		Map<String,Object> p = new HashMap<>();
		List<String> list = new ArrayList<>();
		list.add("a");
		list.add("b");
		p.put("one",list);
		ParamContainer c = new ParamContainer(p);
		Object listOut = c.getParam("one");
		assertTrue(List.class.isAssignableFrom(listOut.getClass()));
		assertEquals(2,((List)listOut).size());
		assertEquals("a",((List)listOut).get(0));
		assertEquals("b",((List)listOut).get(1));		
	}

	@Test
	public void testHash() {
		Map<String,Object> p = new HashMap<>();
		Map<String,Object> map = new HashMap<>();
		map.put("a",1);
		map.put("b",2);
		p.put("one",map);
		ParamContainer c = new ParamContainer(p);
		Object mapOut = c.getParam("one");
		assertTrue(Map.class.isAssignableFrom(mapOut.getClass()));
		assertEquals(2,((Map)mapOut).size());
		assertEquals(1,((Map)mapOut).get("a"));
		assertEquals(2,((Map)mapOut).get("b"));		
	}

}
