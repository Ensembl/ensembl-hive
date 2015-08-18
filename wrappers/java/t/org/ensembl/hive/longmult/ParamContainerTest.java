package org.ensembl.hive.longmult;

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
